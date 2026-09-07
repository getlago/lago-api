# frozen_string_literal: true

require_relative "errors"
require_relative "world"

module BillingMatrix
  class Timeline
    VERBS = %w[
      create_subscription update_subscription terminate_subscription
      ingest_events perform_usage_update perform_billing
      refresh_invoice finalize_invoice void_invoice
      top_up_wallet create_credit_note preview_invoice
      update_plan update_charge update_customer
      update_fixed_charge delete_metric
    ].freeze
    COMMON_STEP_KEYS = %w[at do fails].freeze
    SELECTOR_KEYS = {
      "ingest_events" => %w[events],
      "refresh_invoice" => %w[invoice],
      "finalize_invoice" => %w[invoice],
      "void_invoice" => %w[invoice],
      "top_up_wallet" => %w[wallet],
      "create_credit_note" => %w[invoice],
      "update_charge" => %w[charge],
      "update_fixed_charge" => %w[fixed_charge],
      "delete_metric" => %w[metric]
    }.freeze
    REQUIRED_STEP_KEYS = {
      "ingest_events" => %w[events],
      "create_credit_note" => %w[items]
    }.freeze
    NEEDS_BODY = %w[update_subscription top_up_wallet update_plan update_charge update_customer update_fixed_charge].freeze
    NOT_FAILABLE = %w[perform_usage_update perform_billing void_invoice].freeze
    FIXED_CHARGE_UPDATE_KEYS = %w[invoice_display_name units apply_units_immediately properties tax_codes].freeze
    EVENT_KEYS = %w[code properties count timestamp precise_total_amount_cents].freeze
    TERMINATION_POLICY_KEYS = %i[on_termination_credit_note on_termination_invoice].freeze
    SUBSCRIPTION_KEYS = %w[
      external_id plan_code name billing_time subscription_at ending_at activation_rules plan_overrides
      on_termination_credit_note on_termination_invoice
    ].freeze
    PARAM_KEYS = {
      "create_subscription" => SUBSCRIPTION_KEYS,
      "update_subscription" => SUBSCRIPTION_KEYS - %w[external_id plan_code billing_time] + %w[progressive_billing_disabled usage_thresholds],
      "terminate_subscription" => %w[on_termination_credit_note on_termination_invoice],
      "void_invoice" => %w[generate_credit_note refund_amount credit_amount],
      "top_up_wallet" => %w[granted_credits paid_credits name priority invoice_requires_successful_payment ignore_paid_top_up_limits],
      "create_credit_note" => %w[reason description credit_amount_cents refund_amount_cents offset_amount_cents items]
    }.freeze
    FREE_FORM_PARAMS = %w[preview_invoice].freeze
    CREDIT_NOTE_ITEM_KEYS = %w[fee_type item_code amount_cents].freeze

    def self.verbs = VERBS

    def self.step_keys(verb)
      body = param_keys(verb)
      return nil if body.nil?

      COMMON_STEP_KEYS + SELECTOR_KEYS.fetch(verb, []) + body
    end

    def self.body(step)
      reserved = COMMON_STEP_KEYS + SELECTOR_KEYS.fetch(step.fetch("do"), [])
      step.reject { |key, _| reserved.include?(key.to_s) }
    end

    def self.required_step_keys(verb) = REQUIRED_STEP_KEYS.fetch(verb, [])

    def self.needs_body?(verb) = NEEDS_BODY.include?(verb)

    def self.failable?(verb) = !NOT_FAILABLE.include?(verb)

    def self.param_keys(verb)
      case verb
      when *FREE_FORM_PARAMS then nil
      when "update_plan" then World::KEYS.fetch("plan") + %w[charges usage_thresholds cascade_updates]
      when "update_charge" then World::KEYS.fetch("charges") - %w[metric] + %w[cascade_updates]
      when "update_customer" then World::KEYS.fetch("customer") - %w[external_id]
      when "update_fixed_charge" then FIXED_CHARGE_UPDATE_KEYS
      else PARAM_KEYS.fetch(verb, [])
      end
    end

    def self.run!(ctx, steps)
      steps.each_with_index { |step, index| new(ctx, step, index).run! }
      nil
    end

    def initialize(ctx, step, index)
      @ctx = ctx
      @step = step
      @index = index
    end

    def run!
      raise Unsupported, "#{label}: unknown timeline verb #{verb.inspect}" unless VERBS.include?(verb)

      ctx.travel_to_and_run(at) do
        if fails?
          raise Unsupported, "#{label}: `fails: true` is not supported for #{verb}" unless self.class.failable?(verb)

          public_send(verb, raise_on_error: false)
          stash_error!
        else
          public_send(verb)
        end
      end
    rescue Error
      raise
    rescue => e
      raise Error, "#{label} failed: #{e.class}: #{e.message}"
    end

    def create_subscription(**api)
      spec = params
      body = {
        external_customer_id: ctx.customer.external_id,
        external_id: spec.fetch(:external_id, "sub"),
        plan_code: spec.fetch(:plan_code) { ctx.plan.code },
        billing_time: spec.fetch(:billing_time, "calendar")
      }
      body.merge!(spec.slice(:name, :subscription_at, :ending_at, :activation_rules))
      body[:plan_overrides] = resolve_plan_overrides(spec[:plan_overrides]) if spec[:plan_overrides]

      response = ctx.create_subscription(body, as: :json, **api)
      return response unless ok?

      ctx.subscription = Subscription.find(response.dig(:subscription, :lago_id))
      policy = spec.slice(*TERMINATION_POLICY_KEYS)
      if policy.any?
        ctx.update_subscription(ctx.subscription, policy)
        ctx.subscription.reload
      end
      response
    end

    def update_subscription(**api)
      body = params.dup
      body[:plan_overrides] = resolve_plan_overrides(body[:plan_overrides]) if body[:plan_overrides]
      response = ctx.update_subscription(ctx.subscription, body, **api)
      ctx.subscription.reload if ok?
      response
    end

    def terminate_subscription(**api)
      response = ctx.terminate_subscription(ctx.subscription, params: params, **api)
      ctx.subscription.reload if ok?
      response
    end

    def ingest_events(**api)
      step.fetch("events").each do |event|
        event = event.transform_keys(&:to_s)
        payload = {
          code: event["code"] || sole_metric_code,
          external_subscription_id: ctx.subscription.external_id,
          timestamp: event_timestamp(event),
          properties: event["properties"] || {}
        }
        if event.key?("precise_total_amount_cents")
          payload[:precise_total_amount_cents] = event["precise_total_amount_cents"]
        end
        event.fetch("count", 1).times { ctx.create_event(payload.dup, **api) }
      end
    end

    def perform_usage_update
      ctx.perform_usage_update
    end

    def perform_billing
      ctx.perform_billing
    end

    def refresh_invoice(**api)
      ctx.refresh_invoice(target_invoice, **api)
    end

    def finalize_invoice(**api)
      ctx.finalize_invoice(target_invoice, **api)
    end

    def void_invoice
      ctx.void_invoice(target_invoice, params)
      status = ctx.response.status
      raise Error, "void failed with HTTP #{status}: #{ctx.response.body}" if status >= 400
    end

    def top_up_wallet(**api)
      ctx.create_wallet_transaction(params.merge(wallet_id: target_wallet.id), **api)
    end

    def create_credit_note(**api)
      invoice = target_invoice
      body = params.dup
      body[:invoice_id] = invoice.id
      body[:reason] ||= "other"
      body[:items] = Array(body[:items]).map { |item| resolve_credit_note_item(invoice, item) }
      raise Error, "create_credit_note needs at least one item" if body[:items].empty?

      ctx.create_credit_note(body, **api)
    end

    def preview_invoice(**api)
      body = params.dup
      unless body.key?(:plan_code)
        body[:subscriptions] = {external_ids: [ctx.subscription.external_id]}.merge(body[:subscriptions] || {})
      end

      response = ctx.api_call(**api) do
        ctx.post_with_token(
          ctx.organization,
          "/api/v1/invoices/preview",
          {customer: {external_id: ctx.customer.external_id}}.merge(body)
        )
      end
      stash(:preview, response.fetch(:invoice).to_hash) if ok?
      response
    end

    def update_plan(**api)
      body = params.dup
      body[:charges] = body[:charges].map { |charge| resolve_charge_entry(charge) } if body.key?(:charges)
      response = ctx.update_plan(ctx.plan, body, **api)
      ctx.plan.reload if ok?
      response
    end

    def update_charge(**api)
      charge = target_charge
      body = params.dup
      body[:charge_model] ||= charge.charge_model
      body[:properties] = charge.properties unless body.key?(:properties)
      ctx.update_plan_charge(ctx.plan, charge.code, body, **api)
    end

    def update_customer(**api)
      body = World.customer_params(params).merge(external_id: ctx.customer.external_id)
      response = ctx.create_or_update_customer(body, **api)
      ctx.customer.reload if ok?
      response
    end

    # PUT /subscriptions/:external_id/fixed_charges/:code — the subscription-level endpoint, which
    # is the one that decides between a units-only override and a plan clone.
    def update_fixed_charge(**api)
      fixed_charge = target_fixed_charge
      response = ctx.update_subscription_fixed_charge(ctx.subscription, fixed_charge.code, params, **api)
      ctx.subscription.reload if ok?
      response
    end

    def delete_metric(**api)
      metric = target_metric
      ctx.api_call(**api) do
        ctx.delete_with_token(ctx.organization, "/api/v1/billable_metrics/#{metric.code}")
      end
    end

    private

    attr_reader :ctx, :step, :index

    def verb = step.fetch("do")

    def at
      value = step.fetch("at")
      value.respond_to?(:iso8601) ? value.iso8601 : value.to_s
    end

    def fails? = step["fails"] == true

    def label = "step #{index + 1} (#{verb} at #{at})"

    def params
      @params ||= self.class.body(step).deep_symbolize_keys
    end

    def ok? = ctx.response.status < 400

    def stash_error!
      status = ctx.response.status
      raise Error, "#{label} is marked `fails: true` but the API answered HTTP #{status}" if status < 400

      body = ctx.json
      body = {} unless body.is_a?(Hash)
      stash(:error, {
        "status" => status,
        "code" => body[:code],
        "error_details" => body[:error_details]&.deep_stringify_keys
      })
    end

    def stash(name, value)
      ctx.singleton_class.attr_accessor(name) unless ctx.respond_to?(:"#{name}=")
      ctx.public_send(:"#{name}=", value)
    end

    def sole_metric_code
      ctx.billable_metric&.code ||
        raise(Error, "#{label}: event has no `code` and the setup does not declare exactly one metric")
    end

    def event_timestamp(event)
      return Time.current.to_f unless event["timestamp"]

      Time.iso8601(event["timestamp"].to_s).to_f
    end

    def target_invoice
      invoices = ctx.customer.invoices.visible.order(:created_at, :id).to_a
      select_record(invoices, step["invoice"], kind: "invoice", identity: %i[invoice_type status])
    end

    def select_record(records, selector, kind:, identity:)
      selector = "last" if selector.nil?
      record =
        case selector
        when "first" then records.first
        when "last" then records.last
        when Hash
          filters = selector.transform_keys(&:to_s).except("index")
          scoped = records.select { |candidate| filters.all? { |field, value| candidate.public_send(field).to_s == value.to_s } }
          scoped[selector["index"] || -1]
        else
          raise InvalidRow, "#{label}: `#{kind}` selector must be first, last or a mapping, got #{selector.inspect}"
        end

      record || raise(Error, "#{label}: no #{kind} matched #{selector.inspect}; customer has #{records.size}: " \
                             "#{records.map { |candidate| identity.map { |field| candidate.public_send(field) } }.inspect}")
    end

    def target_wallet
      wallets = ctx.customer.wallets.order(:created_at).to_a
      code = step["wallet"]
      if code
        wallets.find { |wallet| wallet.code == code } ||
          raise(Error, "#{label}: no wallet with code #{code.inspect}; customer has #{wallets.map(&:code).inspect}")
      elsif wallets.size == 1
        wallets.first
      else
        raise Error, "#{label}: customer has #{wallets.size} wallets; name one with `wallet: <code>`"
      end
    end

    def target_charge
      charges = ctx.plan.charges.parents.to_a
      code = step["charge"]
      if code
        charges.find { |charge| charge.code == code } ||
          raise(Error, "#{label}: plan has no charge with code #{code.inspect}; it has #{charges.map(&:code).inspect}")
      elsif charges.size == 1
        charges.first
      else
        raise Error, "#{label}: plan has #{charges.size} charges; name one with `charge: <code>`"
      end
    end

    def target_fixed_charge
      fixed_charges = ctx.subscription.reload.plan.fixed_charges.to_a
      code = step["fixed_charge"]
      if code
        fixed_charges.find { |fixed_charge| fixed_charge.code == code } ||
          raise(Error, "#{label}: the subscription's plan has no fixed charge with code #{code.inspect}; " \
                       "it has #{fixed_charges.map(&:code).inspect}")
      elsif fixed_charges.size == 1
        fixed_charges.first
      else
        raise Error, "#{label}: the subscription's plan has #{fixed_charges.size} fixed charges; name one with `fixed_charge: <code>`"
      end
    end

    def target_metric
      metrics = ctx.organization.billable_metrics.to_a
      code = step["metric"]
      if code
        metrics.find { |metric| metric.code == code } ||
          raise(Error, "#{label}: no billable metric with code #{code.inspect}; the organization has #{metrics.map(&:code).inspect}")
      elsif metrics.size == 1
        metrics.first
      else
        raise Error, "#{label}: the organization has #{metrics.size} metrics; name one with `metric: <code>`"
      end
    end

    def resolve_credit_note_item(invoice, item)
      item = item.transform_keys(&:to_s)
      unknown = item.keys - CREDIT_NOTE_ITEM_KEYS
      raise InvalidRow, "#{label}: credit note item has unknown key(s) #{unknown.inspect}" if unknown.any?

      fee_type = item.fetch("fee_type") { raise InvalidRow, "#{label}: credit note item needs a fee_type" }
      candidates = invoice.fees.select { |fee| fee.fee_type == fee_type.to_s }
      candidates.select! { |fee| fee.item_code == item["item_code"] } if item.key?("item_code")

      case candidates.size
      when 1 then {fee_id: candidates.first.id, amount_cents: item.fetch("amount_cents")}
      when 0 then raise Error, "#{label}: invoice has no #{fee_type} fee to credit; fees present: " \
                               "#{invoice.fees.map { |fee| [fee.fee_type, fee.item_code] }.inspect}"
      else raise Error, "#{label}: #{candidates.size} #{fee_type} fees match; add item_code to pick one " \
                        "(#{candidates.map(&:item_code).inspect})"
      end
    end

    def resolve_charge_entry(entry)
      entry = entry.dup
      code = entry.delete(:metric)
      return entry unless code

      metric = ctx.organization.billable_metrics.find_by(code:) ||
        raise(Error, "#{label}: update_plan names metric #{code.inspect}, which does not exist")
      entry.merge(billable_metric_id: metric.id)
    end

    def resolve_plan_overrides(overrides)
      resolved = overrides.deep_symbolize_keys
      plan = ctx.plan
      if resolved[:fixed_charges]
        resolved[:fixed_charges] = resolved[:fixed_charges].map do |entry|
          resolve_override_entry(entry, plan.fixed_charges.parents, "fixed charge")
        end
      end
      if resolved[:charges]
        resolved[:charges] = resolved[:charges].map do |entry|
          resolve_override_entry(entry, plan.charges.parents, "charge")
        end
      end
      resolved
    end

    def resolve_override_entry(entry, records, kind)
      return entry if entry[:id] || entry[:code].nil?

      record = records.find_by(code: entry[:code]) ||
        raise(Error, "#{label}: plan_overrides names #{kind} #{entry[:code].inspect}, which the plan does not have; " \
                     "it has #{records.pluck(:code).inspect}")
      entry.merge(id: record.id)
    end
  end
end
