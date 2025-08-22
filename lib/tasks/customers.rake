# frozen_string_literal: true

namespace :customers do
  desc "Generate Slug for Customers"
  task generate_slug: :environment do
    Customer.unscoped.order(:created_at).find_each(&:save)
  end

  desc "Migrate customer to a new billing entity"
  task migrate_to_new_entity: :environment, [:customer_external_id, :billing_entity_code] do |t, args|
    customer_external_id = args[:customer_external_id]
    billing_entity_code = args[:billing_entity_code]

    cust = Customer.find_by(external_id: customer_external_id)
    new_be = cust.organization.billing_entities.find_by(code: billing_entity_code)

    raise "Wallets not implemented" if cust.wallets.any?
    raise "Taxes not implemented" if cust.taxes.any?
    raise "Coupons not implemented" if cust.coupons.any?

    raise "Customer has dunning campaigns triggered" if  cust.last_dunning_campaign_attempt != 0
    raise "Customer has dunning campaigns triggered" unless cust.last_dunning_campaign_attempt_at.nil?
    # we need tests on usage
    raise "Customer has a subscription with lifetime usage" if cust.subscriptions.any? { |sub| sub.lifetime_usage&.current_usage_amount_cents.to_i > 0 }
    raise "customer has a subscription with a plan that is pay_in_advance" if cust.subscriptions.any? { |sub| sub.plan.pay_in_advance? }
    raise "Customer has an unknown integration customer" if cust.integration_customers.any? { |int_cust| int_cust.type != "IntegrationCustomers::AnrokCustomer" && int_cust.type != "IntegrationCustomers::NetsuiteCustomer" }
    raise "Customer should not have any credit notes" if cust.credit_notes.any?
    raise "Customer should not have payment requests" if cust.payment_requests.any?
    raise "Metadata is not implemented" if cust.metadata.any?
    raise "Invoice custom sections are not implemented" if cust.applied_invoice_custom_sections.any?

    ActiveRecord::Base.transaction do
      cust.discard

      new_cust = cust.dup
      new_cust.billing_entity = new_be
      new_cust.deleted_at = nil
      new_cust.payment_receipt_counter = 0
      new_cust.sequential_id = nil
      new_cust.slug = nil
      new_cust.save!

      cust.subscriptions.each do |sub|
        if sub.active?
          new_sub = sub.dup
          new_sub.customer = new_cust
          sub.update(on_termination_invoice: :skip)
          Subscriptions::TerminateService.call(subscription: sub, async: false)
          new_sub.save!
          new_ltu = sub.lifetime_usage.dup
          new_ltu.subscription = new_sub
          new_ltu.save!
          # LifetimeUsages::RecalculateAndCheckJob.perform_now(sub.reload.lifetime_usage)
        else
          new_sub = sub.dup
          new_sub.customer = new_cust
          new_sub.save!
        end
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

      # wallets can have top up rules
      cust.wallets.each do |wallet|
        new_wallet = wallet.dup
        new_wallet.customer = new_cust
        new_wallet.save!
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


# now when sending new usage, wallet is not being pdated as ready_to_be_refreshed