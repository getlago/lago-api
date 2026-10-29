# frozen_string_literal: true

class BaseService
  include AfterCommitEverywhere

  # rubocop:disable ThreadSafety/ClassAndModuleAttributes
  class_attribute :middlewares, instance_writer: false, default: []
  # rubocop:enable ThreadSafety/ClassAndModuleAttributes

  class FailedResult < StandardError
    attr_reader :result, :original_error

    def initialize(result, message, original_error: nil)
      @result = result
      @original_error = original_error

      super(message)
    end
  end

  class ThrottlingError < StandardError
    attr_reader :provider_name

    def initialize(provider_name: nil)
      @provider_name = provider_name

      super(message)
    end

    def message
      "Service #{provider_name} is not available. Try again later."
    end
  end

  class NotFoundFailure < FailedResult
    attr_reader :resource

    def initialize(result, resource:)
      @resource = resource

      super(result, error_code)
    end

    def error_code
      "#{resource}_not_found"
    end
  end

  class MethodNotAllowedFailure < FailedResult
    attr_reader :code

    def initialize(result, code:)
      @code = code

      super(result, code)
    end
  end

  class ValidationFailure < FailedResult
    # One code of the failure, under the path of its field in the request (see Api::V2Errors::FIELD),
    # with the facts that let a client fix its next request (see ValidationMeta::KEYS). Only native v2
    # errors render them. The meta is checked when the entry is built, so that a bad key raises in
    # tests at the line that added it, not in the renderer.
    Entry = Data.define(:field, :code, :meta) do
      def initialize(field:, code:, meta: {})
        super(field:, code:, meta: ValidationMeta.check(meta).freeze)
      end
    end

    # The meta keys of the bounds that the length and numericality validators give as an Integer
    # count, so that a model states each bound once. An exclusive bound (greater_than) or a decimal
    # one has no key yet.
    BOUND_KEYS = {
      greater_than_or_equal_to: %i[min],
      less_than_or_equal_to: %i[max],
      too_short: %i[min_length],
      too_long: %i[max_length],
      wrong_length: %i[min_length max_length]
    }.freeze

    attr_reader :messages

    # The errors of a record, read now: valid? clears them in place, and ActiveModel computes each
    # message when it is read.
    def self.from_errors(result, errors)
      entries = errors.group_by_attribute.flat_map do |field, field_errors|
        field_errors.map { Entry.new(field:, code: it.message, meta: meta_of(it)) }
      end

      new(result, messages: errors.messages, entries:)
    end

    # The bound of its validator, then its `meta:` option, which wins key by key. Its other options are
    # not meta: `value:` echoes the request.
    def self.meta_of(error)
      count = error.options[:count]
      keys = count.is_a?(Integer) ? BOUND_KEYS.fetch(error.type, []) : []
      keys = [] if keys.intersect?(%i[min_length max_length]) && !text?(error)
      meta = error.options.fetch(:meta, {})

      meta.is_a?(Hash) ? keys.index_with(count).merge(meta.symbolize_keys) : meta
    end

    # The length validator also counts the elements of a list, which min_length and max_length do not
    # mean. An error imported from another record reads its value there.
    def self.text?(error)
      error = error.inner_error if error.is_a?(ActiveModel::NestedError)
      value = error.base.read_attribute_for_validation(error.attribute) if error.base.respond_to?(error.attribute)

      value.nil? || value.is_a?(String)
    end
    private_class_method :meta_of, :text?

    # One entry per code, in the order of messages, duplicates kept, each code as it is: v2 renders a
    # code that is not a token as value_is_invalid. Messages that are not a hash become
    # value_is_invalid on base, reported so that their producer gets fixed.
    def self.entries_from(messages)
      if messages.is_a?(Hash)
        messages.flat_map { |field, codes| Array.wrap(codes).map { Entry.new(field:, code: it) } }
      else
        ValidationMeta.report("validation messages are not a Hash: #{messages.class}")
        [Entry.new(field: :base, code: "value_is_invalid")]
      end
    end

    # Entries a service collects itself, with their meta. The messages group their codes by field, as
    # the messages of a record do.
    def self.from_entries(result, entries)
      new(result, messages: entries.group_by(&:field).transform_values { it.map(&:code) }, entries:)
    end

    # messages: {field => [code]}, or one of the String, indexed and nested shapes a few services
    # build, kept as they are. entries: derived from messages when the producer adds no meta.
    def initialize(result, messages:, entries: nil)
      @messages = messages
      @given_entries = entries

      super(result, format_messages)
    end

    # Derived on the first read, which only native v2 does: a v1 or GraphQL failure, whose messages
    # may be nested, never builds them.
    def entries
      @entries ||= (@given_entries || self.class.entries_from(messages)).freeze
    end

    # The same codes on the result of the caller, under the fields the block gives, the meta of each
    # kept: a nested record's errors under the key of its parent, a column under its parameter. A
    # plain ValidationFailure, as the block may rename what a subclass reads its facts from.
    def remap(result, &)
      entries = @given_entries&.map { it.with(field: yield(it.field)) }

      ValidationFailure.new(result, messages: messages.transform_keys(&), entries:)
    end

    private

    def format_messages
      "Validation errors: #{messages.to_json}"
    end
  end

  class ServiceFailure < FailedResult
    attr_reader :code, :error_message

    def initialize(result, code:, error_message:, original_error: nil)
      @code = code
      @error_message = error_message

      super(result, "#{code}: #{error_message}", original_error:)
    end
  end

  class NonRetryableFailure < ServiceFailure; end

  class LockAcquisitionFailure < ServiceFailure; end

  class UnknownTaxFailure < FailedResult
    attr_reader :code, :error_message

    def initialize(result, code:, error_message:)
      @code = code
      @error_message = error_message

      super(result, "#{code}: #{error_message}")
    end
  end

  class ForbiddenFailure < FailedResult
    attr_reader :code

    def initialize(result, code:)
      @code = code

      super(result, code)
    end
  end

  class UnauthorizedFailure < FailedResult
    def initialize(result, message:)
      super(result, message)
    end
  end

  # A provider refusing the organization's own credentials, which the caller cannot fix with its key.
  class ProviderUnauthorizedFailure < UnauthorizedFailure
    attr_reader :provider

    def initialize(result, provider:, message:)
      @provider = provider
      super(result, message:)
    end
  end

  class ProviderFailure < FailedResult
    attr_reader :provider

    def initialize(result, provider:, error:)
      @provider = provider
      super(result, nil, original_error: error)
    end
  end

  class ThirdPartyFailure < FailedResult
    attr_reader :third_party, :error_code, :error_message

    def initialize(result, third_party:, error_code:, error_message:)
      @third_party = third_party
      @error_message = error_message
      @error_code = error_code

      super(result, "#{third_party}: #{error_code} - #{error_message}")
    end
  end

  class TooManyProviderRequestsFailure < FailedResult
    attr_reader :provider_name, :error

    def initialize(result, provider_name:, error:)
      @provider_name = provider_name
      @error = error

      super(result, error.message, original_error: error)
    end
  end

  Result = BaseResult

  def self.activity_loggable(action:, record:, condition: -> { true }, after_commit: true)
    use(Middlewares::ActivityLogMiddleware, action:, record:, condition:, after_commit:)
  end

  # Register a new middleware
  def self.use(middleware_class, *args, on_conflict: :raise, **kwargs)
    existing_middleware = middlewares.map(&:first)

    if !existing_middleware.include?(middleware_class) || on_conflict == :append
      return self.middlewares += [[middleware_class, args, kwargs]]
    end

    # Middleware already exists
    case on_conflict
    when :raise
      raise Middlewares::AlreadyAddedError.new(middleware_class, self)
    when :replace
      self.middlewares[existing_middleware.index(middleware_class)] = [middleware_class, args, kwargs]
    when :ignore
      # Do nothing
    end
  end

  use(Middlewares::LogTracerMiddleware)
  use(Middlewares::DatadogMiddleware) if ENV["DD_AGENT_HOST"].present?

  def self.call(*, **, &)
    new(*, **).call_with_middlewares(&)
  end

  def self.call_async(*, **, &)
    LagoTracer.in_span("#{name}#call_async") do
      new(*, **).call_async(&)
    end
  end

  def self.call!(*, **, &)
    call(*, **, &).raise_if_error!
  end

  def initialize(args = nil)
    @result = self.class::Result.new
    @source = CurrentContext&.source
  end

  def call(**args, &block)
    raise NotImplementedError
  end

  def call!(*, &)
    call(*, &).raise_if_error!
  end

  def call_async(**args, &block)
    raise NotImplementedError
  end

  def call_with_middlewares(&block)
    with_middlewares { call(&block) }
  end

  protected

  attr_writer :result

  # Runs an arbitrary block through the service middleware chain.
  # Used by `call_with_middlewares` and by the TypedResults bridge to wrap
  # legacy named methods with the same instrumentation as a regular `call`.
  def with_middlewares(&block)
    init_middlewares.call(&block)
  end

  private

  attr_reader :result, :source

  def api_context?
    source&.to_sym == :api
  end

  def graphql_context?
    source&.to_sym == :graphql
  end

  def at_time_zone(customer: "customers", billing_entity: "billing_entities")
    Utils::Timezone.at_time_zone_sql(customer:, billing_entity:)
  end

  def init_middlewares
    stack = lambda { |&block| block.call }

    # Initialize middlewares in reverse order (Rake like approach)
    self.class.middlewares.reverse_each do |middleware_klass, args, kwargs|
      current_stack = stack

      stack = lambda do |&block|
        middleware = middleware_klass.new(self, current_stack, *args, **kwargs)
        middleware.call(&block)
      end
    end

    stack
  end
end
