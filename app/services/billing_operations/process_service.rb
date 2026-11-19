# frozen_string_literal: true

module BillingOperations
  class ProcessService < BaseService
    Result = BaseResult[:invoices, :processed_operations_count]
    EmptyInvoice = Class.new(StandardError)
    def initialize(customer:, timestamp:)
      @customer = customer
      @timestamp = timestamp
      super
    end

    def call
      result.invoices = []
      result.processed_operations_count = 0
      Customers::LockService.call!(customer:, scope: :billing_schedule, transaction: false) do
        due_operations.group_by { [invoice_kind(it), invoice_group_key(it)] }.each_value do |batch|
          invoice = process_invoice_batch(batch)
          result.invoices << invoice if invoice
        rescue BaseService::FailedResult => error
          @first_error ||= error
        end
        finalize_generating_invoices
        result.invoices.each(&:reload)
      end
      raise @first_error if @first_error

      result
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :customer, :timestamp

    def due_operations
      customer_contracts = customer.contracts.where(organization_id: customer.organization_id).eligible_for_billing(timestamp)
      operations = customer.billing_operations.due_for_processing(timestamp)
        .where(organization_id: customer.organization_id, action_type: BillingOperation::PERIODIC_ACTIONS.keys)
        .joins(:customer, :contract_rate_card).where(customers: {deleted_at: nil, organization_id: customer.organization_id})
        .merge(ContractRateCard.kept.where(organization_id: customer.organization_id, contract_id: customer_contracts.select(:id)))
        .earliest_per_contract_rate_card

      BillingOperation.from(operations, :billing_operations)
        .includes(contract_rate_card: {contract: :customer, rate_card: {product: :billable_metric}})
        .order(:billing_at, :contract_rate_card_id, :created_at, :id)
    end

    def invoice_kind(operation)
      case operation.action_type
      when "regroup_paid_fees"
        :advance_charges
      else
        :contract
      end
    end

    def invoice_group_key(operation)
      contract = operation.contract_rate_card.contract
      [
        operation.billing_at.in_time_zone(customer.applicable_timezone).to_date,
        contract.consolidate_invoice ? :shared : [operation.contract_rate_card_id, operation.id],
        operation.contract_rate_card.rate_card.currency,
        contract.billing_entity_id || customer.billing_entity_id,
        payment_method_key(contract),
        contract.purchase_order_number
      ]
    end

    def payment_method_key(contract)
      if contract.payment_method_id.present?
        [contract.payment_method_id, contract.payment_method_type]
      elsif contract.payment_method_type == "manual"
        [nil, "manual"]
      elsif customer.default_payment_method.present?
        [customer.default_payment_method.id, "provider"]
      else
        [nil, contract.payment_method_type]
      end
    end

    def process_invoice_batch(operations)
      invoice = nil
      ActiveRecord::Base.transaction(requires_new: true) do
        operations.select! do |operation|
          billing_at = operation.billing_at
          operation.reload(lock: true)
          operation.contract_rate_card.lock!
          next false unless operation.billing_at == billing_at

          operation.due_for_processing?(timestamp:)
        end
        next if operations.empty?

        preload_billing_inputs(operations)
        segments_by_operation = operations.index_with { |operation| resolve_segments(operation) }
        billing_segments = segments_by_operation.values.flatten(1)
        invoice = if billing_segments.any?
          if invoice_kind(operations.first) == :advance_charges
            regroup_paid_fees(operations, billing_segments, segments_by_operation)
          else
            create_contract_invoice(billing_segments, segments_by_operation)
          end
        end
        complete_operations(operations)
        result.processed_operations_count += operations.size
      end
      invoice
    end

    # Locking reloads each operation and its card, which drops what was preloaded with them.
    def preload_billing_inputs(operations)
      ActiveRecord::Associations::Preloader.new(
        records: operations,
        associations: {segments: [:rate_card_rate, :rate_override], contract_rate_card: [
          :organization,
          :terms,
          {product: [:billable_metric, {filters: {values: :billable_metric_filter}}]},
          {rate_card: [:rates, {product: :billable_metric}]},
          {rate_phases: :rate_override},
          {contract: :customer}
        ]}
      ).call
      codes = operations.filter_map { it.contract_rate_card.rate_card.applied_pricing_unit_code }.uniq
      @pricing_units_by_code = codes.any? ? customer.organization.pricing_units.where(code: codes).index_by(&:code) : {}
    end

    # An obsolete terminal renewal bills nothing, but still completes and clears its clock.
    def resolve_segments(operation)
      return [] if obsolete_terminal_renewal?(operation)

      ResolveSegmentsService.call!(operation:, pricing_units_by_code: @pricing_units_by_code).billing_segments
    end

    def obsolete_terminal_renewal?(operation)
      return false unless operation.action_type.in?(BillingOperation::ADVANCE_RENEWALS)

      ended_at = operation.contract_rate_card.contract.billing_ends_at
      ended_at && ended_at <= operation.target_cycle_started_at
    end

    def create_contract_invoice(segments, segments_by_operation)
      contract = segments.first.contract
      invoice = nil
      outputs = {}
      context = nil
      ActiveRecord::Base.transaction(requires_new: true) do
        invoice = Invoices::CreateGeneratingService.call!(
          customer:, billing_entity: contract.billing_entity || customer.billing_entity,
          invoice_type: :contract, invoicing_reason: :subscription_periodic,
          currency: segments.first.currency, datetime: segments.first.billing_at,
          purchase_order_number: contract.purchase_order_number
        ).invoice
        context = customer.applicable_invoice_grace_period(billing_entity: invoice.billing_entity).positive? ? :draft : :finalize
        outputs = BillingOperations::ComputeInvoiceService.call!(
          invoice:, segments_by_operation:, context:
        ).outputs
        raise EmptyInvoice if context == :finalize && invoice.fees.reload.empty?

        Invoices::ApplyInvoiceCustomSectionsService.call!(
          invoice:, resources: segments.map(&:contract).uniq.map do |resource|
            Invoices::ApplyInvoiceCustomSectionsService::Resource.from(resource:)
          end
        )
        if context == :draft
          invoice.update!(status: :draft)
          notify_draft_created(invoice)
        end
      end
      billed_segments = if context == :draft
        segments
      else
        outputs.filter_map { |segment, fees| segment if fees.any? }
      end
      operations_with_billed_segments(billed_segments, segments_by_operation).each { |operation| operation.invoice = invoice }
      invoice
    rescue EmptyInvoice
      nil
    end

    def regroup_paid_fees(operations, segments, segments_by_operation)
      contract = segments.first.contract
      invoice = nil
      ActiveRecord::Base.transaction(requires_new: true) do
        invoice = Invoices::CreateGeneratingService.call!(
          customer:, invoice_type: :advance_charges, currency: segments.first.currency,
          datetime: segments.first.billing_at, skip_charges: true,
          billing_entity: contract.applicable_billing_entity,
          purchase_order_number: contract.purchase_order_number
        ).invoice
        items = segments.map { ::Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: it) }
        contexts = segments.map { Billing::Context.from(contract: it.contract) }
        fee_result = ::Fees::AdvanceChargesService.call!(
          invoice:, billing_contexts: contexts, metered_items: items,
          billing_at: operations.first.billing_at
        )
        invoiced_segments = fee_result.invoiced_metered_items.map(&:billing_segment)
        raise EmptyInvoice if invoice.fees.reload.empty?

        Invoices::AggregateAmountsAndTaxesFromFees.call!(invoice:)
        Invoices::ApplyInvoiceCustomSectionsService.call!(
          invoice:, resources: segments.map(&:contract).uniq.map do |resource|
            Invoices::ApplyInvoiceCustomSectionsService::Resource.from(resource:)
          end
        )
        invoice.update!(payment_status: :succeeded)
        operations_with_billed_segments(invoiced_segments, segments_by_operation).each { |operation| operation.invoice = invoice }
      end
      invoice
    rescue EmptyInvoice
      nil
    end

    # Operations with no billed segments must not inherit another operation's invoice in a consolidated batch.
    def operations_with_billed_segments(billed_segments, segments_by_operation)
      segments_by_operation.filter_map do |operation, segments|
        operation if segments.intersect?(billed_segments)
      end
    end

    # The clock moves to the obligation after this one, in the same transaction as the billing.
    def complete_operations(operations)
      operations.each do |operation|
        operation.update!(processed_at: timestamp)
        operation.contract_rate_card.update!(next_billing_at: next_planned_operation(operation)&.billing_at)
      end
    end

    def next_planned_operation(operation)
      return if obsolete_terminal_renewal?(operation)

      card = operation.contract_rate_card
      return if card.rate_card.rates.empty?

      Schedule::BuildPlannedOperation.call!(
        schedule: Billing::RateCards::BuildScheduleService.call!(contract_rate_card: card).schedule,
        after_operation: operation
      ).planned_operation
    end

    def finalize_generating_invoices
      invoice_ids = customer.billing_operations.completed.where(organization_id: customer.organization_id)
        .joins(:invoice).where(invoices: {status: :generating}).select(:invoice_id)

      customer.invoices.generating.where(organization_id: customer.organization_id, id: invoice_ids)
        .order(:issuing_date, :id).each do |invoice|
        if invoice.advance_charges?
          Invoices::FinalizeAndPublishAdvanceChargesService.call!(invoice:)
        elsif invoice.contract?
          Invoices::FinalizeContractInvoiceService.call!(invoice:)
        end
      end
    end

    def notify_draft_created(invoice)
      customer.flag_wallets_for_refresh
      SendWebhookJob.perform_after_commit("invoice.drafted", invoice)
      Utils::ActivityLog.produce_after_commit(invoice, "invoice.drafted")
      return if invoice.tax_pending?

      SendWebhookJob.perform_after_commit("invoice.ready_to_finalize", invoice)
      Utils::ActivityLog.produce_after_commit(invoice, "invoice.ready_to_finalize")
    end
  end
end
