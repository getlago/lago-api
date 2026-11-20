# frozen_string_literal: true

require_relative "errors"

module BillingMatrix
  # Reads back only the keys `row.expect` actually asserts, as plain Ruby hashes with string
  # keys — no AR objects, no ids, no invoice numbers, no timestamps that aren't themselves under
  # test. `Comparison` never touches the database or an AR object; this is the only file that does.
  #
  # A fee's identity fields (fee_type, item_code, item_type, from_date, to_date) are the one
  # exception to "only what's asserted": they are always included, asserted or not, because
  # `Comparison` needs them to match fees by content instead of by array position.
  module Observe
    FEE_IDENTITY_FIELDS = %w[fee_type item_code item_type from_date to_date].freeze
    INVOICE_INDEX_KEY = /\Ainvoice\[(\d+)\]\z/

    module_function

    def call(ctx, expect)
      deep_stringify(expect).each_with_object({}) do |(key, value), observed|
        case key
        when "invoices"
          observed[key] = invoices_for(ctx).count
        when "invoice"
          invoice = single(invoices_for(ctx))
          observed[key] = invoice_hash(invoice, value) if invoice
        when INVOICE_INDEX_KEY
          invoice = invoices_for(ctx).order(:created_at, :id)[Regexp.last_match(1).to_i - 1]
          observed[key] = invoice_hash(invoice, value) if invoice
        when "wallet"
          wallet = ctx.wallet
          observed[key] = model_hash(wallet.reload, value) if wallet
        when "credit_note"
          credit_note = single(credit_notes_for(ctx))
          observed[key] = model_hash(credit_note, value) if credit_note
        when "subscription"
          subscription = ctx.subscription
          observed[key] = subscription_hash(subscription.reload, value) if subscription
        when "preview"
          observed[key] = preview_hash(ctx, value)
        when "error"
          observed[key] = error_hash(ctx, value)
        else
          raise BillingMatrix::Unsupported, "Observe: unsupported expect key #{key.inspect}"
        end
      end
    end

    def invoices_for(ctx)
      ctx.customer.invoices.reload
    end

    def credit_notes_for(ctx)
      ctx.customer.credit_notes.reload
    end

    def single(scope)
      return nil unless scope.count == 1
      scope.first
    end

    def invoice_hash(invoice, expected)
      hash = model_hash(invoice, expected, skip: ["fees"])
      hash["fees"] = fees_for(invoice, expected["fees"]) if expected.key?("fees")
      hash
    end

    def fees_for(invoice, expected_fee_list)
      requested = expected_fee_list.is_a?(Array) ? expected_fee_list.flat_map(&:keys) : []
      keys = (FEE_IDENTITY_FIELDS + requested.map(&:to_s)).uniq

      invoice.fees.reload.map { |fee| fee_hash(fee, keys) }
    end

    def fee_hash(fee, keys)
      keys.index_with { |key| fee_field(fee, key) }
    end

    def fee_field(fee, key)
      case key
      when "fee_type" then fee.fee_type
      when "item_code" then fee.item_code
      when "item_type" then fee.item_type
      when "from_date" then fee.date_boundaries[:from_date]
      when "to_date" then fee.date_boundaries[:to_date]
      when "fees_count" then raise BillingMatrix::Unsupported, "Observe: fees_count is not a fee-level field"
      else fee.public_send(key)
      end
    end

    def model_hash(model, expected, skip: [])
      expected.each_with_object({}) do |(field, _), hash|
        next if skip.include?(field)
        hash[field] = model_field(model, field)
      end
    end

    def model_field(model, field)
      case field
      when "fees_count" then model.fees.count
      else model.public_send(field)
      end
    end

    # A plan override clones the plan into a child record (Plans::OverrideService sets
    # parent_id), so "the override happened" is observable as the current plan having a
    # parent. Its id is a fresh UUID no row could state, hence a boolean.
    def subscription_hash(subscription, expected)
      expected.each_with_object({}) do |(field, _), hash|
        hash[field] = subscription_field(subscription, field)
      end
    end

    def subscription_field(subscription, field)
      case field
      when "plan_overridden" then !subscription.plan.parent_id.nil?
      when "plan_name" then subscription.plan.name
      when "plan_code" then subscription.plan.code
      else subscription.public_send(field)
      end
    end

    # The preview endpoint is a real API round trip, so its payload comes back through
    # V1::InvoiceSerializer / V1::FeeSerializer rather than off an AR object: fee identity is
    # nested under `item`, everything else (including from_date/to_date, merged in flat by the
    # serializer) already matches the AR-observed field names one for one.
    def preview_hash(ctx, expected)
      invoice = stashed!(ctx, :preview)
      hash = expected.each_with_object({}) do |(field, _), acc|
        next if field == "fees"
        acc[field] = (field == "fees_count") ? (invoice["fees"] || []).length : invoice[field]
      end
      hash["fees"] = preview_fees(invoice["fees"] || [], expected["fees"]) if expected.key?("fees")
      hash
    end

    def preview_fees(fees_json, expected_fee_list)
      requested = expected_fee_list.is_a?(Array) ? expected_fee_list.flat_map(&:keys) : []
      keys = (FEE_IDENTITY_FIELDS + requested.map(&:to_s)).uniq

      fees_json.map do |fee_json|
        keys.index_with { |key| preview_fee_field(fee_json, key) }
      end
    end

    def preview_fee_field(fee_json, key)
      case key
      when "fee_type" then fee_json.dig("item", "type")
      when "item_code" then fee_json.dig("item", "code")
      when "item_type" then fee_json.dig("item", "item_type")
      else fee_json[key]
      end
    end

    def error_hash(ctx, expected)
      error = stashed!(ctx, :error)
      expected.each_with_object({}) { |(field, _), hash| hash[field] = error[field] }
    end

    # A row that asserts `preview:` or `error:` but whose timeline produced neither is a
    # broken row, not an empty observation. Reading the last response instead would let the
    # assertion silently describe some unrelated call.
    def stashed!(ctx, name)
      value = ctx.public_send(name)
      if value.nil?
        raise Unsupported, "expect.#{name} was asserted but no timeline step produced a #{name} " \
                           "(a preview_invoice step, or a step marked `fails: true`)"
      end
      deep_stringify(value)
    end

    def deep_stringify(value)
      case value
      when Hash
        value.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify(v) }
      when Array
        value.map { |v| deep_stringify(v) }
      else
        value
      end
    end
  end
end
