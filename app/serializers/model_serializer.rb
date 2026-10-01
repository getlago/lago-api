# frozen_string_literal: true

class ModelSerializer
  NO_EXPANDABLE_RELATIONS = {}.freeze

  attr_reader :model, :options

  # Names a v2 `show` accepts in `expand`, mapped to what a single record loads in advance:
  # nil for a computed value or a list built by its own query. Renders through the private
  # `expand_<name>`. Internal options (`:counts`, `:deleted_at`) are never listed.
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
    self.class.expandable_relations.keys.select { include?(it) }.index_with { send(:"expand_#{it}") }
  end
end
