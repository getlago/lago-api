# frozen_string_literal: true

module Api
  # `expand` of the native v2 endpoints: on `show` only, one level deep, limited to the list of
  # the serializer declared with `expandable_with`. Anything else is a 400, never ignored:
  # `expand_not_supported` where nothing is expandable, `invalid_expand` for a value the list
  # lacks or a form that cannot be read.
  module Expandable
    extend ActiveSupport::Concern

    NUMERIC_INDEX = /\A\d+\z/
    # The query string keys carrying `expand`: bare, or followed by brackets.
    QUERY_KEY = /\Aexpand(?:\[|\z)/
    INDEXED_QUERY_KEY = /\Aexpand\[\d+\]\z/

    included { before_action :validate_expand! }

    class_methods do
      def expandable_with(serializer)
        private(define_method(:expandable_serializer) { serializer })
      end
    end

    private

    def expandable_serializer = nil

    # A form that cannot be read is reported as such wherever it is sent.
    def validate_expand!
      if expand_values.nil?
        invalid_expand_error(reason: "malformed", allowed_values: allowed_expansion_names)
      elsif expand_values.any? && allowed_expansions.empty?
        expand_not_supported_error
      elsif (invalid = expand_values - allowed_expansion_names).any?
        invalid_expand_error(invalid_values: invalid, allowed_values: allowed_expansion_names)
      end
    end

    # Passed as `includes:` by every v2 render.
    def serializer_includes = [*requested_expansions, :deleted_at]

    def preload_expansions(record)
      associations = requested_expansions.filter_map { expandable_serializer.expandable_relations[it] }
      if associations.any?
        ActiveRecord::Associations::Preloader.new(records: [record], associations:).call
      end

      record
    end

    def allowed_expansions
      if action_name == "show" && expandable_serializer
        expandable_serializer.expandable_relations.keys
      else
        []
      end
    end

    def allowed_expansion_names = allowed_expansions.map(&:to_s)

    # Symbols taken from the list itself: a request value is never symbolized.
    def requested_expansions = allowed_expansions.select { expand_values.include?(it.to_s) }

    # expand[]=a, expand=a&expand=b, expand[0]=a: trimmed, without blanks or duplicates; nil when
    # malformed.
    def expand_values
      return @expand_values if defined?(@expand_values)

      values = raw_expand_values
      @expand_values = (values.map(&:strip).compact_blank.uniq if values&.all?(String))
    end

    # Rails keeps only the last value of a key sent twice, so the raw query string is read too:
    # repeated bare keys (`expand=a&expand=b`, how Python requests, Go and URLSearchParams send a
    # list) are that list, and the forms Rails would reduce to one of their values are malformed.
    def raw_expand_values
      # Read first: a query string Rails cannot parse is its own 400, before the raw one is parsed.
      expand = params[:expand]
      query = query_expand_params

      if reduced_by_rails?(query)
        nil
      elsif query.key?("expand")
        # A bare key without a value (`?expand=a&expand`) parses as nil: a blank to drop.
        query["expand"].compact
      else
        parsed_expand_values(expand)
      end
    end

    # Every `expand` key of the query string, with all the values it was sent with. Split by the
    # parser Rails builds `params` with, so that any query string it accepted parses here too.
    def query_expand_params
      ActionDispatch::QueryParser.each_pair(request.query_string.to_s)
        .select { |key, _| key.match?(QUERY_KEY) }
        .group_by(&:first)
        .transform_values { |pairs| pairs.map(&:last) }
    end

    # A bare key next to a bracketed one, a repeated index, or `expand` in both the query string
    # and the body: Rails keeps one of the values and drops the others.
    def reduced_by_rails?(query)
      (query.key?("expand") && query.size > 1) ||
        query.any? { |key, values| key.match?(INDEXED_QUERY_KEY) && values.many? } ||
        (query.any? && request.request_parameters.key?("expand"))
    end

    def parsed_expand_values(expand)
      case expand
      when nil then []
      when String then [expand]
      when Array then expand
      when ActionController::Parameters then expand.values if expand.keys.all?(NUMERIC_INDEX)
      end
    end

    def invalid_expand_error(details)
      invalid_request_error(code: "invalid_expand", error_details: {expand: details})
    end

    # On an action other than `show`, or on an endpoint without an expand list.
    def expand_not_supported_error
      reason = expandable_serializer ? "show_only" : "not_expandable"

      invalid_request_error(code: "expand_not_supported", error_details: {expand: {reason:, invalid_values: expand_values}})
    end
  end
end
