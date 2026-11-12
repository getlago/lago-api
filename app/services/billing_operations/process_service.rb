# frozen_string_literal: true

module BillingOperations
  class ProcessService < BaseService
    Result = BaseResult[:invoices]
    EmptyInvoice = Class.new(StandardError)
    ELIGIBLE_ACTION_TYPES = %w[
      renew_fixed_advance
      close_fixed_arrears
      close_metered_arrears
      renew_recurring_metered_advance
      regroup_paid_fees
    ].freeze

    def initialize(customer:, timestamp:)
      @customer = customer
      @timestamp = timestamp
      super
    end

    def call
      result.invoices = []
      Customers::LockService.call!(customer:, scope: :billing_schedule, transaction: false) do
        due_operations.group_by { [invoice_kind(it), invoice_group_key(it)] }.each_value do |batch|
          invoice = process_invoice_batch(batch)
          result.invoices << invoice if invoice
        rescue BaseService::FailedResult => error
          @first_error ||= error
        end
      end
      raise @first_error if @first_error

      result
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :customer, :timestamp

    def due_operations
      ContractRateCard.due_for_billing(timestamp)
        .where(organization_id: customer.organization_id, contracts: {customer_id: customer.id})
        .includes(:terms, contract: :customer, rate_card: {product: :billable_metric})
        .filter_map do |contract_rate_card|
          action_type = contract_rate_card.periodic_billing_action
          next unless action_type

          billing_at = contract_rate_card.next_billing_at
          activation_operation = BillingOperation.pending
            .where(
              organization_id: customer.organization_id, customer_id: customer.id, contract_rate_card:,
              action_type:, causation_type: "contract_activation"
            )
            .order(:created_at, :id)
            .first

          if activation_operation
            activation_operation.billing_at = billing_at
            activation_operation
          else
            BillingOperation.new(
              organization_id: customer.organization_id, customer:, contract_rate_card:, action_type:,
              causation_type: "periodic_continuation", billing_at:
            )
          end
        end
        .sort_by { [it.billing_at, it.contract_rate_card_id] }
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
          if operation.persisted?
            billing_at = operation.billing_at
            operation.reload(lock: true)
            operation.contract_rate_card.lock!
            next false unless operation.contract_rate_card.next_billing_at == billing_at

            if operation.causation_type == "contract_activation"
              operation.billing_at = billing_at
            end
            operation.due_for_processing?(timestamp:)
          else
            operation.contract_rate_card.lock!
            operation.contract_rate_card.next_billing_at == operation.billing_at
          end
        end
        next if operations.empty?

        operation_segments = operations.index_with { |operation| resolve_operation(operation) }.compact
        segments = operation_segments.values.flat_map(&:segments)
        invoice = if segments.any?
          if regroup_batch?(operations)
            regroup_paid_fees(operations, segments, operation_segments)
          else
            create_contract_invoice(segments, operation_segments)
          end
        end
        complete_operations(operation_segments)
      end
      finalize_generating_invoices(operations.filter_map(&:invoice_id))
      invoice&.reload
      invoice
    end

    def resolve_operation(operation)
      return unless eligible?(operation)

      if obsolete_terminal_renewal?(operation)
        operation.contract_rate_card.update!(next_billing_at: nil) if operation.new_record?
        return
      end

      ResolveSegmentsService.call!(operation:)
    end

    def obsolete_terminal_renewal?(operation)
      return false unless operation.action_type.in?(%w[renew_fixed_advance renew_recurring_metered_advance])

      ended_at = [operation.contract_rate_card.contract.ended_at, operation.contract_rate_card.contract.terminated_at].compact.min
      ended_at && ended_at <= (operation.target_cycle_started_at || operation.billing_at)
    end

    def eligible?(operation)
      ELIGIBLE_ACTION_TYPES.include?(operation.action_type)
    end

    def create_contract_invoice(segments, operation_segments)
      contract = segments.first.contract
      invoice = nil
      outputs = {}
      ActiveRecord::Base.transaction(requires_new: true) do
        invoice = Invoices::CreateGeneratingService.call!(
          customer:, billing_entity: contract.billing_entity || customer.billing_entity,
          invoice_type: :contract, invoicing_reason: :subscription_periodic,
          currency: segments.first.currency, datetime: segments.first.billing_at,
          purchase_order_number: contract.purchase_order_number
        ).invoice
        context = customer.applicable_invoice_grace_period(billing_entity: invoice.billing_entity).positive? ? :draft : :finalize
        outputs = BillingOperations::ComputeInvoiceService.call!(
          invoice:, billing_segments: segments, context:
        ).outputs
        raise EmptyInvoice if invoice.fees.reload.empty?

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
      billed_segments = outputs.filter_map { |segment, fees| segment if fees.any? }
      operations_with_billed_segments(billed_segments, operation_segments).each { |operation| operation.invoice = invoice }
      invoice
    rescue EmptyInvoice
      nil
    end

    def regroup_batch?(operations)
      operations.all? { |operation| operation.action_type == "regroup_paid_fees" }
    end

    def regroup_paid_fees(operations, segments, operation_segments)
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
        operations_with_billed_segments(invoiced_segments, operation_segments).each { |operation| operation.invoice = invoice }
      end
      invoice
    rescue EmptyInvoice
      nil
    end

    # Operations with no billed segments must not inherit another operation's invoice in a consolidated batch.
    def operations_with_billed_segments(segments, operation_segments)
      operation_segments.filter_map do |operation, resolution|
        operation if (resolution.segments & segments).any?
      end
    end

    def complete_operations(operation_segments)
      operation_segments.each do |operation, resolution|
        operation.update!(processed_at: timestamp)

        ContractRateCards::AdvanceBillingClockService.call!(operation:, resolution:)
      end
    end

    def finalize_generating_invoices(invoice_ids)
      Invoice.where(id: invoice_ids, status: :generating)
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
