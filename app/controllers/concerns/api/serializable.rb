# frozen_string_literal: true

module Api
  # How a native v2 controller renders its records, declared once at its top:
  #
  #   serializable_with ::V2::ProductSerializer
  #
  # It generates `render_product(record)` and `render_products(records)`, which build the
  # serializer, the cursor page and the expansions, so that the actions never do.
  #
  # `expand` is checked on every action, declared or not, before any lookup. On an `expand_on`
  # action, it embeds the records the serializer declares with `expandable`, one level deep.
  # Any other value it receives is a 400, never ignored: `expand_not_supported` where nothing
  # expands, `invalid_expand` for a name the serializer does not declare or a form that cannot be
  # read. Rails keeps only the last of a repeated bare key (`expand=a&expand=b`), as for any
  # other parameter.
  module Serializable
    extend ActiveSupport::Concern

    NUMERIC_INDEX = /\A\d+\z/

    Serialization = Data.define(:serializer, :root, :collection, :expand_on)

    # Included by Api::V2::BaseController, whose cursor and 400 body it uses, so that the
    # validation runs before every callback of a subclass.
    included { before_action :validate_expand! }

    class_methods do
      # `root` is the JSON key of a record, the singular controller name unless given. A list
      # renders under its plural.
      def serializable_with(serializer, root: controller_name&.singularize, expand_on: %i[show])
        expand_on = expand_on.map(&:to_s).freeze

        raise ArgumentError, "#{self} needs a root to render #{serializer}" if root.blank?
        # A list stays flat: its queries and its payload would grow with the size of the page.
        raise ArgumentError, "#{self} cannot expand its index" if expand_on.include?("index")

        serialization = Serialization.new(serializer:, root: root.to_s, collection: root.to_s.pluralize, expand_on:)

        private(define_method(:serialization) { serialization })
        private(define_method(:"render_#{serialization.root}") { |record| render_resource(record) })
        private(define_method(:"render_#{serialization.collection}") { |records, &map| render_collection(records, &map) })
      end
    end

    private

    # Without `serializable_with`, a controller renders on its own and expands nothing.
    def serialization = nil

    # With the expansions the request asked for, on an `expand_on` action.
    def render_resource(record)
      render(json: serialization.serializer.new(record, root_name: serialization.root, includes: requested_expansions))
    end

    # One page and its cursors on a cursor-paginated index, the whole list anywhere else. A block
    # maps the records before they render, for a list paged on other rows than it renders.
    def render_collection(records)
      if cursor_paginated_index?
        page = ::CursorPagination::Page.new(records:, cursor:)
        records = page.records
        meta = page.meta
      end
      records = yield(records) if block_given?

      render(json: ::CollectionSerializer.new(records, serialization.serializer, collection_name: serialization.collection, meta:))
    end

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

    def allowed_expansions
      if serialization&.expand_on&.include?(action_name)
        serialization.serializer.expandable_names
      else
        []
      end
    end

    def allowed_expansion_names = allowed_expansions.map(&:to_s)

    # Symbols taken from the serializer: a request value is never symbolized.
    def requested_expansions = allowed_expansions.select { expand_values.include?(it.to_s) }

    # expand[]=a, expand=a, expand[0]=a: trimmed, without blanks or duplicates; nil when malformed.
    # Read from `params`, as Rails parses any other parameter: a bare key sent twice keeps its last
    # value.
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

    # `action_not_expandable` where another action of the controller expands, `not_expandable`
    # where none does.
    def expand_not_supported_error
      reason = expandable_elsewhere? ? "action_not_expandable" : "not_expandable"

      invalid_request_error(code: "expand_not_supported", error_details: {expand: {reason:, invalid_values: expand_values}})
    end

    def expandable_elsewhere?
      serialization.present? && serialization.expand_on.any? && serialization.serializer.expandable_names.any?
    end
  end
end
