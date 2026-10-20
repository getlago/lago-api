# frozen_string_literal: true

class ModelSerializer
  # Prepended by `expandable`, so that a serializer cannot declare an expansion and forget to
  # render it.
  module RendersExpansions
    def serialize
      super.merge(expanded_payload)
    end
  end

  NO_EXPANSIONS = {}.freeze

  # Set once per serializer, when its class is loaded, through `expandable`.
  class_attribute :expansions, instance_accessor: false, instance_predicate: false, default: NO_EXPANSIONS # rubocop:disable ThreadSafety/ClassAndModuleAttributes

  attr_reader :model, :options

  # Lets a native v2 endpoint embed `model.<name>` on `expand[]=<name>`, rendered by `serializer`
  # without includes, so that the embedded record stays flat. It comes last in `serialize`.
  def self.expandable(name, serializer:)
    prepend(RendersExpansions)

    self.expansions = expansions.merge(name.to_sym => serializer).freeze
  end

  def self.expandable_names = expansions.keys

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

  # The declared expansions found in `includes`, in their declared order: Api::Serializable
  # passes the requested ones, and a nil record renders as null.
  def expanded_payload
    self.class.expansions.each_with_object({}) do |(name, serializer), payload|
      next unless include?(name)

      payload[name] = model.public_send(name)&.then { serializer.new(it).serialize }
    end
  end
end
