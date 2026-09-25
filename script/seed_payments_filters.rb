# frozen_string_literal: true

# Run in the development API container:
#   bundle exec rails runner script/seed_payments_filters.rb
# Creates an isolated, idempotent fixture organization. Credentials and the
# expected-record manifest are written under tmp/, never to stdout or git.
raise "This seed is only for development" unless Rails.env.development?

require "factory_bot_rails"
FactoryBot.find_definitions if FactoryBot.factories.none?
ActiveJob::Base.queue_adapter = :test

slug = "payments-filters"
credentials_path = Rails.root.join("tmp/payments_filters_credentials.json")
organization = Organization.find_by(slug:)

unless organization
  password = SecureRandom.base64(24)
  Organization.transaction do
    organization = FactoryBot.create(:organization, slug:, name: "Payments filters QA", webhook_url: nil)
    organization.default_billing_entity.update!(timezone: "America/Los_Angeles")
    user = FactoryBot.create(:user, email: "payments-filters@example.com", password:)
    FactoryBot.create(:membership, organization:, user:, roles: [:admin])
    customers = Array.new(3) do |index|
      FactoryBot.create(:customer, organization:, external_id: "cust_#{index + 1}",
        name: "Payments QA #{index + 1}", email: "customer#{index + 1}@example.com")
    end
    providers = [
      FactoryBot.create(:stripe_provider, organization:, code: "qa_stripe", name: "QA Stripe"),
      FactoryBot.create(:gocardless_provider, organization:, code: "qa_gocardless", name: "QA GoCardless")
    ]
    connections = customers.to_h do |customer|
      [customer.id, providers.map do |provider|
        factory = provider.is_a?(PaymentProviders::StripeProvider) ? :stripe_customer : :gocardless_customer
        FactoryBot.create(factory, organization:, customer:, payment_provider: provider, code: provider.code)
      end]
    end
    amounts = [0, 99, 100, 999, 1000, 2500, 5000, 5001, 2_147_483_647,
      2_147_483_648, 5_000_000_000, 9_007_199_254_740_992, 9_007_199_254_740_993,
      9_223_372_036_854_775_807]
    method_types = %w[card sepa_debit us_bank_account bacs_debit link boleto crypto customer_balance]
    zone = ActiveSupport::TimeZone[organization.timezone]
    dates = [zone.local(2026, 9, 1), zone.local(2026, 9, 7).end_of_day,
      zone.local(2026, 8, 31).end_of_day, zone.local(2026, 9, 8), zone.local(2026, 9, 4, 12)]

    30.times do |index|
      customer = customers[index % customers.length]
      amount_cents = amounts[index % amounts.length]
      currency = index.even? ? "EUR" : "USD"
      invoice_status = case index
      when 28 then :draft # Draft invoices are visible in the existing payments query.
      when 29 then :open # Open invoices are excluded by Invoice::VISIBLE_STATUS.
      else :finalized
      end
      invoice = FactoryBot.create(:invoice, organization:, customer:, status: invoice_status,
        currency:, total_amount_cents: amount_cents, issuing_date: Date.new(2026, 9, 1))
      invoice.update!(number: format("QA-INV-%03d", index + 1))
      payable = if index % 4 == 2
        second_invoice = FactoryBot.create(:invoice, organization:, customer:, status: :finalized,
          currency:, total_amount_cents: 0, issuing_date: Date.new(2026, 9, 1))
        second_invoice.update!(number: (index == 2) ? "LAG-1234-001-002" : format("QA-INV-%03d-B", index + 1))
        FactoryBot.create(:payment_request, organization:, customer:, amount_cents:, amount_currency: currency,
          invoices: [invoice, second_invoice])
      else
        invoice
      end
      manual = index % 3 == 0
      provider = manual ? nil : providers[index % providers.length]
      connection = manual ? nil : connections.fetch(customer.id)[index % providers.length]
      method_type = method_types[index % method_types.length]
      method = if connection
        FactoryBot.create(:payment_method, organization:, customer:, payment_provider: provider,
          payment_provider_customer: connection, provider_method_id: "qa_method_#{index}",
          provider_method_type: method_type, is_default: false)
      end
      method_data = if manual || index % 3 == 1
        {}
      else
        {type: method_type, brand: "visa", last4: "4242"}
      end
      payment = FactoryBot.create(:payment, organization:, customer:, payable:, amount_cents:,
        amount_currency: currency, payment_type: manual ? "manual" : "provider",
        reference: manual ? "QA manual #{index + 1}" : nil,
        payment_provider: provider, payment_provider_customer: connection, payment_method: method,
        provider_payment_id: manual ? nil : "pi_3_qa_#{index + 1}",
        provider_payment_method_data: method_data,
        payable_payment_status: Payment::PAYABLE_PAYMENT_STATUS[index % 4],
        created_at: dates[index % dates.length])
      if index.even?
        FactoryBot.create(:payment_receipt, organization:, payment:, number: format("RCPT-2026-%04d", index / 2 + 1))
      end
    end
    File.write(credentials_path, JSON.pretty_generate({email: user.email, password:, api_key: organization.api_keys.first.value}), mode: "w", perm: 0o600)
  end
end

records = Payment.where(organization:).order(:created_at, :id).map do |payment|
  {
    id: payment.id,
    amount_cents: payment.amount_cents.to_s,
    currency: payment.amount_currency,
    payment_status: payment.payable_payment_status,
    payment_type: payment.payment_type,
    payable_type: payment.payable_type,
    external_customer_id: payment.customer.external_id,
    invoice_ids: payment.invoices.pluck(:id),
    invoice_numbers: payment.invoice_numbers,
    receipt_number: payment.payment_receipt&.number,
    payment_provider_type: payment.payment_provider_type,
    payment_method_type: payment.provider_payment_method_data["type"].presence || payment.payment_method&.provider_method_type,
    provider_payment_id: payment.provider_payment_id,
    reference: payment.reference,
    created_at: payment.created_at.iso8601(6),
    visible: !payment.payable.is_a?(Invoice) || Invoice::VISIBLE_STATUS.key?(payment.payable.status.to_sym)
  }
end
File.write(Rails.root.join("tmp/payments_filters_manifest.json"), JSON.pretty_generate({organization_id: organization.id, timezone: organization.timezone, payments: records}))
Rails.logger.info "Payments QA seed ready: #{records.count} payments, #{records.count { |record| record[:visible] }} visible."
Rails.logger.info "Credentials: tmp/payments_filters_credentials.json (local only)."
Rails.logger.info "Expected records: tmp/payments_filters_manifest.json."
