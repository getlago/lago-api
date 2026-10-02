# frozen_string_literal: true

module Api
  # `expand` of the native v2 endpoints: on `show` only, one level deep, limited to the list of
  # the serializer declared with `expandable_with`. Anything else is a 400, never ignored.
  module Expandable
    extend ActiveSupport::Concern

    NUMERIC_INDEX = /\A\d+\z/

    included { before_action :validate_expand! }

    class_methods do
      def expandable_with(serializer)
        private(define_method(:expandable_serializer) { serializer })
      end
    end

    private

    def expandable_serializer = nil

    def validate_expand!
      if expand_values.nil?
        invalid_expand_error(reason: "malformed", allowed_values: allowed_expansion_names)
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

    # expand[]=a, expand=a, expand[0]=a: trimmed, without blanks or duplicates; nil when malformed.
    def expand_values
      return @expand_values if defined?(@expand_values)

      values = raw_expand_values
      @expand_values = (values.map(&:strip).compact_blank.uniq if values&.all?(String))
    end

    def raw_expand_values
      expand = params[:expand]
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
  end
end
