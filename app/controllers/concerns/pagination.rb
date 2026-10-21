# frozen_string_literal: true

module Pagination
  extend ActiveSupport::Concern

  # Default number of records per page
  DEFAULT_PAGE_SIZE = 100
  # Largest per_page accepted on /api/v1 lists when LAGO_API_PAGINATION_MAX_PAGE_SIZE is not a positive integer
  DEFAULT_MAX_PAGE_SIZE = 200
  # The TTL for caching the number of records
  DEFAULT_TTL = 30.minutes.freeze

  included do
    # A controller sets `self.max_page_size = n` to cap its own page size below the organization
    # or global limit.
    # rubocop:disable ThreadSafety/ClassAndModuleAttributes
    class_attribute :max_page_size, instance_writer: false
    # rubocop:enable ThreadSafety/ClassAndModuleAttributes
  end

  def self.max_page_size
    max_page_size = Integer(ENV["LAGO_API_PAGINATION_MAX_PAGE_SIZE"].to_s, 10, exception: false)
    max_page_size&.positive? ? max_page_size : DEFAULT_MAX_PAGE_SIZE
  end

  def pagination_metadata(records, **count_params)
    current_page = prev_page = next_page = total_pages = nil
    total_count = _count_total(**count_params) do
      if clickhouse_relation?(records)
        # Handle Clickhouse intermittent errors
        Events::Stores::Utils::ClickhouseConnection.with_retry { records.total_count }
      else
        records.total_count
      end
    end

    if total_count.positive?
      current_page = records.current_page
      total_pages = _total_pages(records, total_count)
      next_page = current_page + 1 if current_page < total_pages
      prev_page = current_page - 1 if current_page > 1
    end

    {
      "current_page" => current_page.to_i,
      "next_page" => next_page,
      "prev_page" => prev_page,
      "total_pages" => total_pages.to_i,
      "total_count" => total_count
    }
  end

  private

  def page_number
    params[:page].presence&.to_i || 1
  end

  # The requested page size, or the default page size within the limit when none is given.
  def page_size
    params[:per_page].presence&.to_i || [default_page_size, page_size_limit].min
  end

  def default_page_size
    DEFAULT_PAGE_SIZE
  end

  def validate_pagination_params
    errors = {
      page: pagination_param_error(:page, max: nil),
      per_page: pagination_param_error(:per_page, max: page_size_limit)
    }.compact

    validation_errors(errors:) if errors.any?
  end

  # A blank value is treated as absent. Only plain positive decimals are valid: Integer() would also
  # accept forms such as 010, +5, 1_000 or a leading space.
  def pagination_param_error(name, max:)
    return if params[name].blank?

    value = params[name].to_s
    if value.match?(/\A[1-9]\d*\z/) && (max.nil? || value.to_i <= max)
      nil
    else
      ["value_is_out_of_range"]
    end
  end

  # The effective page size limit of the controller: its own cap, if any, within the
  # organization or global limit.
  def page_size_limit
    [self.class.max_page_size, organization_max_page_size || Pagination.max_page_size].compact.min
  end

  # An organization cached by ApiKeys::CacheService before the column existed does not have it.
  def organization_max_page_size
    current_organization.pagination_max_page_size if current_organization.has_attribute?(:pagination_max_page_size)
  end

  def clickhouse_relation?(records)
    records.respond_to?(:klass) && records.klass < Clickhouse::BaseRecord
  end

  # Computes total pages from the record count.
  # For kaminari collections, derives it from limit_value to avoid an extra COUNT(*) query.
  # For custom result objects (e.g. PastUsageQuery::Result), uses the precomputed value.
  def _total_pages(records, total_count)
    return records.total_pages unless records.respond_to?(:limit_value)

    (total_count.to_f / records.limit_value).ceil
  end

  def _count_total(key: nil, organization_id: nil, params: nil, ttl: DEFAULT_TTL)
    # backward-compatibility: skip caching if it is not requested explicitly
    return yield unless key && organization_id && params

    # prepare the key for caching
    hash_data = _deep_sort(params.except(:page).merge(organization_id:))
    hash = Digest::SHA256.hexdigest(hash_data.to_json)
    cache_key = "pagination_count/#{key}/#{hash}"

    # Re-calculate on the last page because the number of records could have changed.
    # If the count is small (less than the page size), caching is useless but re-querying is acceptable.
    cached = Rails.cache.read(cache_key)
    return cached if cached.to_i > page_size * page_number

    yield.tap { |count| Rails.cache.write(cache_key, count, expires_in: ttl) }
  end

  # Recursively converts hashes into sorted arrays of pairs
  # to ensure deterministic JSON serialization regardless of key order.
  def _deep_sort(obj)
    case obj
    when Hash, ActionController::Parameters
      obj.to_h.map { |k, v| [k.to_s, _deep_sort(v)] }.sort_by(&:first)
    when Array then obj.map { |v| _deep_sort(v) }
    else obj
    end
  end
end
