# frozen_string_literal: true

class ModelSerializer
  NO_EXPANDABLE_RELATIONS = {}.freeze

  attr_reader :model, :options

  # Names a v2 `show` accepts in `expand`, mapped to what a single record loads in advance:
  # nil for a computed value or a list built by its own query. Each renders through `expand`.
  # Internal options (`:counts`, `:deleted_at`, `:usec_timestamps`) are never listed.
  def self.expandable_relations
    NO_EXPANDABLE_RELATIONS
  end

  # The possible values for the options are:
  # - includes: Specify the relation to include in the payload
  #   Expected format: [:customer, {plan: [:charges]}]
  #
  #   Hash values can be passed to the relation serializer
  #   when used with `included_relations`.
  #   Example:
  #     included_relations(:plan, default: [:charges])`
  def initialize(model, options = {})
    @model = model
    @options = options
  end

  def serialize
    {id: model.id}
  end

  def to_json(options = {})
    {
      root_name => serialize
    }.to_json(options)
  end

  def root_name
    options.fetch(:root_name, :data)
  end

  # Check if a relation should be included in the payload
  def include?(value)
    includes = options[:includes]
    return false if includes.blank?

    includes.any? do |include|
      next value == include if include.is_a?(Symbol)
      next include.key?(value) if include.is_a?(Hash)

      false
    end
  end

  # Retrieve the relations to be included by a subserializer
  # When the relation valus is symbol, it returns the default values
  # When the relation is a hash key, it will return the matching value
  def included_relations(value, default: [])
    includes = options[:includes]
    return default if includes.blank?

    include = includes.find do |include|
      next value == include if include.is_a?(Symbol)
      next include.key?(value) if include.is_a?(Hash)
    end

    return default if include.is_a?(Symbol) || include.nil?

    include[value]
  end

  private

  def expanded_payload
    self.class.expandable_relations.keys.select { include?(it) }.index_with { expand(it) }
  end

  # Renders one name of the expand list. A serializer with a list overrides it with a `case` on
  # the names, falling back to `super` for any other.
  def expand(name)
    raise NotImplementedError, "#{self.class} cannot expand #{name}"
  end

  # Includes of a record rendered inside this one: never expansions, so it stays flat.
  def nested_includes(forward: [])
    [:deleted_at, :usec_timestamps, *forward].select { include?(it) }
  end

  # At the microsecond precision the columns store when the render passes `:usec_timestamps`, as
  # the native v2 endpoints do. At whole seconds otherwise, so webhooks and activity logs keep theirs.
  def format_time(value)
    value&.iso8601(include?(:usec_timestamps) ? 6 : 0)
  end

  # A calendar day, never a datetime: it has no time zone of its own.
  def format_date(value)
    value&.iso8601
  end

  def deleted_at_payload
    include?(:deleted_at) ? {deleted_at: model.deleted_at&.iso8601} : {}
  end
end
