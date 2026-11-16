# frozen_string_literal: true

# Per-connection concurrency rule of the integration jobs. sidekiq-throttled calls it with the
# serialized ActiveJob arguments on every fetch and finalize of every provider's job, so it never
# raises and never loads a record: anything it cannot resolve gets no limit.
# It has no organization context: it reads ids by primary key from the job's own global id and
# returns only a number and a digest.
module IntegrationThrottleKey
  # Matched as a string, with pick only: a row of a type without a model cannot be instantiated.
  QUICKBOOKS_TYPE = "Integrations::QuickbooksIntegration"
  LIMIT = 3
  NO_CONNECTION_SUFFIX = "none"
  CACHE_TTL = 1.hour
  THREAD_KEY = :integration_throttle_key
  RECORD_KEYS = %w[invoice credit_note payment].freeze
  RECORD_CLASSES = %w[Invoice CreditNote Payment].freeze

  # The gem asks for the limit, then for the key suffix, on the thread that later finalizes the job.
  # The suffix reuses the resolution of the limit for the same arguments: a second resolution that
  # fails or changes would count the job under "none", or free a slot in another set than the one it took.
  def self.limit(*args)
    id = integration_id(args)
    Thread.current[THREAD_KEY] = [args, id]
    id ? LIMIT : nil
  end

  def self.key_suffix(*args)
    resolved_args, resolved_id = Thread.current[THREAD_KEY]
    id = (resolved_args == args) ? resolved_id : integration_id(args)
    id ? Digest::SHA256.hexdigest(id) : NO_CONNECTION_SUFFIX
  end

  # A payload of any other shape (no argument, not a hash, malformed global id) raises here and
  # resolves to nil, like a database or cache error.
  def self.integration_id(args)
    payload = args.first.with_indifferent_access

    if payload.key?(:integration)
      gid = GlobalID.parse(payload[:integration][:_aj_globalid])
      (gid.model_name == QUICKBOOKS_TYPE) ? gid.model_id : nil
    else
      gid = GlobalID.parse(payload.values_at(*RECORD_KEYS).compact.first[:_aj_globalid])
      cached_integration_id(gid)
    end
  rescue
    nil
  end

  def self.cached_integration_id(gid)
    if RECORD_CLASSES.include?(gid.model_name)
      # A nil result is stored too, so a customer without QuickBooks costs one lookup per hour.
      Rails.cache.fetch("integration_throttle_key/#{gid.model_name}/#{gid.model_id}", expires_in: CACHE_TTL) do
        lookup(gid.model_name.constantize, gid.model_id)
      end
    end
  end

  def self.lookup(klass, id)
    customer_id = klass.unscoped.where(id:).pick(:customer_id)
    return unless customer_id

    links = IntegrationCustomers::BaseCustomer.where(customer_id:)
    # The record jobs sync to the first accounting_kind link of the customer (NetSuite or Xero).
    # A customer that has one is not counted against QuickBooks. Revisit when QuickBooks joins accounting_kind.
    return if links.accounting_kind.exists?

    links
      .joins(:integration)
      .where(integrations: {type: QUICKBOOKS_TYPE})
      .order("integrations.id")
      .pick("integrations.id")
  end

  private_class_method :integration_id, :cached_integration_id, :lookup
end
