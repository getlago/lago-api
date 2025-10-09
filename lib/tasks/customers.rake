# frozen_string_literal: true

namespace :customers do
  desc "Generate Slug for Customers"
  task generate_slug: :environment do
    Customer.unscoped.order(:created_at).find_each(&:save)
  end

  # WARNING! Potentially dangerous task
  desc "Migrate customer to a new billing entity. This version is actual on August 2025, please, check before running if anything needs to be updated"
  task :migrate_to_new_entity, [:organization_id, :customer_external_id, :billing_entity_code] => :environment do |_task, args|
    customer_external_id = args[:customer_external_id]
    billing_entity_code = args[:billing_entity_code]

    cust = Customer.find_by(external_id: customer_external_id)
    new_be = cust.organization.billing_entities.find_by(code: billing_entity_code)

    # wallets are now implemented, but require a change in the codebase
    # taxes should be easy to implement, but current customers do not have taxes, so we're not getting into it
    raise "Taxes not implemented" if cust.taxes.any?
    # current customer do not have coupons. when implementing coupons, pay attention on currencies
    raise "Coupons not implemented" if cust.coupons.any?

    # triggered dunning_campaign can be not a problem if all payments and payment_requests are managed - to figure it out with the organization
    raise "Customer has dunning campaigns triggered" if cust.last_dunning_campaign_attempt != 0
    raise "Customer has dunning campaigns triggered" unless cust.last_dunning_campaign_attempt_at.nil?
    raise "Customer should not have payment requests" if cust.payment_requests.any?
    # pay_in_advance will immediately trigger the invoice, which is not a desired behaviour
    raise "customer has a subscription with a plan that is pay_in_advance" if cust.subscriptions.any? { |sub| sub.plan.pay_in_advance? }
    raise "Customer has an unknown integration customer" if cust.integration_customers.any? { |int_cust| int_cust.type != "IntegrationCustomers::AnrokCustomer" && int_cust.type != "IntegrationCustomers::NetsuiteCustomer" }
    # customers this script was created for, did not have credit_notes, metadata, invoice custom sections
    raise "Customer should not have any credit notes" if cust.credit_notes.any?
    raise "Metadata is not implemented" if cust.metadata.any?
    raise "Invoice custom sections are not implemented" if cust.applied_invoice_custom_sections.any?
    # progressively billed usage cannot be shared and we're risking to trigger again the tresholds
    raise "Customer has progressive billing invoices" if cust.invoices.progressive_billing.any?

    ActiveRecord::Base.transaction do
      cust.discard

      new_cust = cust.dup
      new_cust.billing_entity = new_be
      new_cust.deleted_at = nil
      new_cust.payment_receipt_counter = 0
      new_cust.sequential_id = nil
      new_cust.slug = nil
      new_cust.last_dunning_campaign_attempt = 0
      new_cust.last_dunning_campaign_attempt_at = nil
      new_cust.save!

      cust.subscriptions.active.each do |sub|
        puts "Terminating active subscription with id #{sub.id} for customer #{cust.id}"
        sub.update(on_termination_invoice: :skip)
        Subscriptions::TerminateService.call(subscription: sub, async: false)
      end

      cust.integration_customers.each do |int_cust|
        if int_cust.type == "IntegrationCustomers::AnrokCustomer"
          new_int_cust = int_cust.dup
          new_int_cust.customer = new_cust
          new_int_cust.save!
        elsif int_cust.type == "IntegrationCustomers::NetsuiteCustomer"
          # we decided that they will need to manually create new integration customers
        else
          raise "Unknown integration customer type: #{int_cust.type}"
        end
      end

      cust.payment_provider_customers.each do |payment_provider_cust|
        new_payment_provider_cust = payment_provider_cust.dup
        new_payment_provider_cust.customer = new_cust
        new_payment_provider_cust.save!
      end

      # do we want to create wallet with 0 values, and create an inbound transaction of granted credits???
      cust.wallets.each do |wallet|
        wallet_params = {
          organization_id: new_cust.organization_id,
          customer: new_cust,
          name: wallet.name,
          rate_amount: wallet.rate_amount,
          currency: wallet.currency,
          expiration_at: wallet.expiration_at,
          invoice_requires_successful_payment: wallet.invoice_requires_successful_payment,
          applies_to: {
            fee_types: wallet.allowed_fee_types
          },
          granted_credits: wallet.credits_balance.to_s
        }
        new_wallet = Wallets::CreateService.call!(params: wallet_params).wallet

        wallet.recurring_transaction_rules.each do |rule|
          new_rule = rule.dup
          new_rule.wallet = new_wallet
          new_rule.save!
        end
        wallet.wallet_targets.each do |target|
          new_target = target.dup
          new_target.wallet = new_wallet
          new_target.save!
        end
      end

      Customers::TerminateRelationsService.call(customer: cust)
    end
  end
end
