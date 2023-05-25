# frozen_string_literal: true

namespace :invoices do
  desc 'Generate Number for Invoices'
  task generate_number: :environment do
    Invoice.order(:created_at).find_each(&:save)
  end

  desc 'Populate invoice_subscriptions join table'
  task handle_subscriptions: :environment do
    Invoice.order(:created_at).find_each do |invoice|
      subscription_id = invoice&.subscription_id
      next unless subscription_id

      invoice_subscription = InvoiceSubscription.find_by(
        invoice_id: invoice.id,
        subscription_id:,
      )

      next if invoice_subscription

      InvoiceSubscription.create!(invoice_id: invoice.id, subscription_id:)
    end
  end

  desc 'Fill missing customer_id'
  task fill_customer: :environment do
    Invoice.where(customer_id: nil).find_each do |invoice|
      invoice.update!(customer_id: invoice.subscriptions&.first&.customer_id)
    end
  end

  desc 'Fill invoice Taxes rate'
  task fill_taxes_rate: :environment do
    Invoice.where(taxes_rate: nil).find_each do |invoice|
      invoice.update!(
        taxes_rate: (invoice.taxes_amount_cents.fdiv(invoice.amount_cents) * 100).round(2),
      )
    end
  end

  desc 'Set currency to fees'
  task set_currency_to_fees: :environment do
    Invoice.find_each do |invoice|
      invoice.fees.each do |fee|
        fee.update(
          amount_currency: invoice.currency,
          vat_amount_currency: invoice.currency,
        )
      end
    end
  end

  desc 'Fill invoice credit amount'
  task fill_credit_amount: :environment do
    Invoice.where(credit_amount_cents: 0).find_each do |invoice|
      transaction_amount = invoice.wallet_transactions.sum(:amount)
      currency = invoice.amount.currency
      rounded_amount = transaction_amount.round(currency.exponent)
      prepaid_credit_amount = rounded_amount * currency.subunit_to_unit

      invoice.update!(
        credit_amount_cents: invoice.credits.sum(&:amount_cents) + prepaid_credit_amount,
        credit_amount_currency: invoice.currency,
      )
    end
  end

  desc 'Fill invoice organization from customers'
  task fill_organization: :environment do
    # NOTE: when upgrading from before v0.24.0-beta, versions table does not exists
    #       but PaperTrail is loaded in the model.
    #       So we need to turn it off temporary to ensure migration passes
    PaperTrail.request.disable_model(Invoice)

    Invoice.where(organization_id: nil).find_each do |invoice|
      invoice.update!(organization_id: invoice.customer.organization_id)
    end

    PaperTrail.request.enable_model(Invoice)
  end
end
