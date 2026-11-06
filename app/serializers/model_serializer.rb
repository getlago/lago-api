# frozen_string_literal: true

class ModelSerializer
  # Prepended by `timestamps` and `expandable`, so that a serializer cannot declare a field and
  # forget to render it. One module, so that the expansions come last whatever the declaration order.
  module RendersDeclaredFields
    def serialize
      super.merge(timestamps_payload, expanded_payload)
    end
  end

  Expansion = Data.define(:serializer, :webhooks)

  NO_EXPANSIONS = {}.freeze
  NO_TIMESTAMPS = [].freeze

  # Set once per serializer, when its class is loaded, through `expandable` and `timestamps`.
  class_attribute :expansions, instance_accessor: false, instance_predicate: false, default: NO_EXPANSIONS # rubocop:disable ThreadSafety/ClassAndModuleAttributes
  class_attribute :timestamp_names, instance_accessor: false, instance_predicate: false, default: NO_TIMESTAMPS # rubocop:disable ThreadSafety/ClassAndModuleAttributes

  attr_reader :model, :options

  # Renders each `model.<name>`, or what a private method of the serializer with that name returns,
  # with `format_time`. V2 serializers declare their datetimes with it.
  def self.timestamps(*names)
    prepend(RendersDeclaredFields)

    self.timestamp_names = [*timestamp_names, *names.map(&:to_sym)].freeze
  end

  # Lets a native v2 endpoint embed `model.<name>` on `expands[]=<name>`, or what a private method
  # of the serializer with that name returns, for records that are ordered or computed. One record
  # or a list, each rendered by `serializer` with `nested_options` only, so that it stays flat. It
  # comes last in `serialize`. `webhooks: true` also embeds it in the record's webhooks: see
  # `for_webhook!`.
  def self.expandable(name, serializer:, webhooks: false)
    prepend(RendersDeclaredFields)

    self.expansions = expansions.merge(name.to_sym => Expansion.new(serializer:, webhooks:)).freeze
  end

  def self.expandable_names = expansions.keys

  # The expansions a webhook embeds, the ones declared with `webhooks: true`, in their declared
  # order: `webhook: true` adds them. The activity log of a catalog invoice reads them too.
  def self.webhook_includes = expansions.filter_map { |name, expansion| name if expansion.webhooks }

  # The possible values for the options are:
  # - includes: Specify the relation to include in the payload
  #   Expected format: [:customer, {plan: [:charges]}]
  #
  #   Hash values can be passed to the relation serializer
  #   when used with `included_relations`.
  #   Example:
  #     included_relations(:plan, default: [:charges])`
  # - webhook: true renders the record as its webhooks send it, with `webhook_includes`, and false
  #   keeps a webhook body flat. Either way a webhook cannot ask for expansions: its own includes
  #   are internal ones, such as `:counts`.
  def initialize(model, options = {})
    @model = model
    @options = options.key?(:webhook) ? webhook_options(options) : options
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

  # Turns this render into a webhook body, as Webhooks::BaseService asks for it: with
  # `webhook: true`, unless the service chose a `webhook` option. A serializer without expansions
  # has none to add.
  def for_webhook!
    unless self.class.expandable_names.empty? || options.key?(:webhook)
      @options = webhook_options(options.merge(webhook: true))
    end

    self
  end

  private

  # At the microsecond precision the columns store when the render passes `:usec_timestamps`, as
  # the native v2 endpoints do. At whole seconds otherwise, so webhooks and activity logs keep theirs.
  def format_time(value)
    value&.iso8601(include?(:usec_timestamps) ? 6 : 0)
  end

  # A date column renders as a calendar day: it has no time of day, so no precision to choose.
  def format_date(value)
    value&.iso8601
  end

  # An expansion reaches a webhook only through `webhooks: true`, so that the declarations stay
  # the one list of what webhooks embed.
  def webhook_options(options)
    includes = Array(options[:includes])

    if self.class.expandable_names.intersect?(includes.flat_map { it.is_a?(Hash) ? it.keys : it })
      raise ArgumentError, "#{self.class.name} embeds an expansion in a webhook only through `webhooks: true`"
    elsif options[:webhook]
      options.merge(includes: [*self.class.webhook_includes, *includes])
    else
      options
    end
  end

  # Options of a record rendered inside this one: the timestamp precision it was given, never an
  # expansion, so that the record stays flat.
  def nested_options
    include?(:usec_timestamps) ? {includes: %i[usec_timestamps]} : {}
  end

  def timestamps_payload
    self.class.timestamp_names.index_with { format_time(declared_value(it)) }
  end

  # The declared expansions found in `includes`, in their declared order: Api::Serializable
  # passes the requested ones, and a nil record renders as null.
  def expanded_payload
    self.class.expansions.each_with_object({}) do |(name, expansion), payload|
      next unless include?(name)

      payload[name] = render_expansion(declared_value(name), expansion.serializer)
    end
  end

  # Only a method the serializer defines itself overrides the model: one inherited from
  # ModelSerializer or Kernel never does.
  def declared_value(name)
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
