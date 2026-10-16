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

  # Lets a native v2 endpoint embed `model.<name>` on `expands[]=<name>`, or what a private method
  # of the serializer with that name returns, for records that are ordered or computed. One record
  # or a list, each rendered by `serializer` with `nested_options` only, so that it stays flat. It
  # comes last in `serialize`.
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

  # At the microsecond precision the columns store when the render passes `:usec_timestamps`, as
  # the native v2 endpoints do. At whole seconds otherwise, so webhooks and activity logs keep theirs.
  def format_time(value)
    value&.iso8601(include?(:usec_timestamps) ? 6 : 0)
  end

  # For a date column: a calendar day has no time zone, so no precision to choose.
  def format_date(value)
    value&.iso8601
  end

  # Options of a record rendered inside this one: the timestamp precision it was given, never an
  # expansion, so that the record stays flat.
  def nested_options
    include?(:usec_timestamps) ? {includes: %i[usec_timestamps]} : {}
  end

  # The declared expansions found in `includes`, in their declared order: Api::Serializable
  # passes the requested ones, and a nil record renders as null.
  def expanded_payload
    self.class.expansions.each_with_object({}) do |(name, serializer), payload|
      next unless include?(name)

      payload[name] = render_expansion(expanded_records(name), serializer)
    end
  end

  # Only a method the serializer defines itself overrides the model: one inherited from
  # ModelSerializer or Kernel never does.
  def expanded_records(name)
    if respond_to?(name, true) && method(name).owner < ModelSerializer
      send(name)
    else
      model.public_send(name)
    end
  end

  def render_expansion(records, serializer)
    case records
    when nil then nil
    when Array, ActiveRecord::Relation then records.map { serializer.new(it, nested_options).serialize }
    else serializer.new(records, nested_options).serialize
    end
  end
end
