# frozen_string_literal: true

class UsageFilters
  # filter_by_charge - when set, allows to calculate usage only for a specific charge and not all charges of a plan
  #          example: Charge.last
  #
  # filter_by_group  - when set, calculates usage only for specific {pricing_group_key: value}.
  #                    Note that if sent, will ignore grouping by this pricing_group_key
  #          example: {user_id: '123'}
  #
  # skip_grouping    - when set, will ignore grouping by pricing_group_keys
  # full_usage       - when set, will ignore boundaries and will return usage since subscription.started_at

  attr_reader :filter_by_charge_id, :filter_by_charge_code, :filter_by_group, :skip_grouping, :full_usage

  def self.init_from_params(params)
    group = params[:filter_by_group]
    group = group.to_unsafe_h if group.respond_to?(:to_unsafe_h)

    new(
      filter_by_charge_id: params[:filter_by_charge_id],
      filter_by_charge_code: params[:filter_by_charge_code],
      filter_by_group: group,
      skip_grouping: ActiveModel::Type::Boolean.new.cast(params[:skip_grouping]),
      full_usage: ActiveModel::Type::Boolean.new.cast(params[:full_usage])
    )
  end

  def initialize(filter_by_charge_id: nil, filter_by_charge_code: nil, filter_by_group: nil, skip_grouping: false, full_usage: false)
    @filter_by_charge_id = filter_by_charge_id
    @filter_by_charge_code = filter_by_charge_code
    @filter_by_group = filter_by_group&.transform_values { |v| Array(v) }
    @skip_grouping = skip_grouping
    @full_usage = full_usage
  end

  def has_charge_filter?
    filter_by_charge_id.present? || filter_by_charge_code.present?
  end

  NONE = new.freeze
end
