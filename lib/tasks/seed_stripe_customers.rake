# frozen_string_literal: true

require "faker"

namespace :seed do
  desc "Create 100 customers with Stripe payment provider, payment methods, and one-off invoices"
  task stripe_customers: :environment do
    # Check if Faker is available
    unless defined?(Faker)
      puts "ERROR: Faker gem is not available in this environment."
      puts "Faker is only available in development, test, and staging environments."
      exit 1
    end

    # Configuration - Update these values as needed
    ORGANIZATION_NAME = ENV.fetch("SEED_ORGANIZATION_NAME", "QA4 Org Name")
    PAYMENT_PROVIDER_CODE = ENV.fetch("SEED_STRIPE_PROVIDER_CODE", "test4")
    ADDON_CODE = ENV.fetch("SEED_ADDON_CODE", "consulting") #setup_fee
    CUSTOMER_COUNT = ENV.fetch("SEED_CUSTOMER_COUNT", 1).to_i # change to 100
    CURRENCY = ENV.fetch("SEED_CURRENCY", "EUR")

    # Stripe test token for creating payment methods (only works in Stripe TEST mode)
    # tok_visa creates a new unique PaymentMethod for each customer
    # See: https://docs.stripe.com/testing#cards
    STRIPE_TEST_TOKEN = ENV.fetch("SEED_STRIPE_TOKEN", "tok_visa")

    puts "Starting to seed #{CUSTOMER_COUNT} customers with Stripe integration..."
    puts "-" * 60

    # Find organization
    organization = Organization.find_by!(name: ORGANIZATION_NAME)
    puts "✓ Found organization: #{organization.name} (#{organization.id})"

    # Find Stripe payment provider
    stripe_provider = if PAYMENT_PROVIDER_CODE.present?
      organization.stripe_payment_providers.find_by!(code: PAYMENT_PROVIDER_CODE)
    else
      organization.stripe_payment_providers.first!
    end
    puts "✓ Found Stripe provider: #{stripe_provider.code} (#{stripe_provider.id})"

    # Validate Stripe API key
    unless stripe_provider.secret_key.present?
      raise "Stripe provider does not have a secret key configured"
    end
    api_key = stripe_provider.secret_key

    # Find billing entity
    billing_entity = organization.default_billing_entity
    puts "✓ Found billing entity: #{billing_entity.name}"

    # Find add-on for one-off invoices
    addon = organization.add_ons.find_by!(code: ADDON_CODE)
    puts "✓ Found add-on: #{addon.name} (#{addon.code})"

    puts "-" * 60
    puts "Creating customers..."

    created_count = 0
    failed_count = 0
    skipped_count = 0

    CUSTOMER_COUNT.times do |i|
      external_id = "seed_stripe_cust_#{SecureRandom.hex(8)}"
      firstname = Faker::Name.first_name
      lastname = Faker::Name.last_name

      begin
        ActiveRecord::Base.transaction do
          # Step 1: Create the customer with Stripe payment provider
          customer_result = Customers::CreateService.call(
            organization_id: organization.id,
            billing_entity_code: billing_entity.code,
            external_id: external_id,
            firstname: firstname,
            lastname: lastname,
            name: "#{firstname} #{lastname}",
            email: Faker::Internet.email(name: "#{firstname} #{lastname}"),
            currency: CURRENCY,
            payment_provider: "stripe",
            payment_provider_code: stripe_provider.code,
            provider_customer: {
              sync: true,  # Run synchronously - don't enqueue async job
              sync_with_provider: true,
              provider_payment_methods: ["card"]
            }
          )

          customer_result.raise_if_error!
          customer = customer_result.customer

          # The Stripe customer should already be created synchronously due to sync: true
          provider_customer = customer.stripe_customer
          provider_customer&.reload

          # Step 3: Create and attach payment method via Stripe API
          if provider_customer&.provider_customer_id?
            begin
              # Create a unique PaymentMethod for this customer using a test token
              # tok_visa can be reused - it creates a new unique PM each time
              payment_method = ::Stripe::PaymentMethod.create(
                {
                  type: "card",
                  card: {token: STRIPE_TEST_TOKEN}
                },
                {api_key: api_key}
              )

              # Attach the PaymentMethod to the Stripe Customer
              attached_pm = ::Stripe::PaymentMethod.attach(
                payment_method.id,
                {customer: provider_customer.provider_customer_id},
                {api_key: api_key}
              )

              # Set as default payment method
              ::Stripe::Customer.update(
                provider_customer.provider_customer_id,
                {invoice_settings: {default_payment_method: attached_pm.id}},
                {api_key: api_key}
              )

              # Update provider customer with payment method ID
              provider_customer.update!(payment_method_id: attached_pm.id)

              puts "  ✓ Customer #{i + 1}/#{CUSTOMER_COUNT}: #{firstname} #{lastname} - Stripe: #{provider_customer.provider_customer_id}, PM: #{attached_pm.id}"
            rescue ::Stripe::InvalidRequestError => e
              puts "  ⚠ Customer #{i + 1}/#{CUSTOMER_COUNT}: #{firstname} #{lastname} - Created but payment method failed: #{e.message}"
            end
          else
            puts "  ⚠ Customer #{i + 1}/#{CUSTOMER_COUNT}: #{firstname} #{lastname} - Created but no Stripe customer ID"
          end

          # Step 4: Create one-off invoice
          invoice_result = Invoices::CreateOneOffService.call(
            customer: customer,
            currency: CURRENCY,
            fees: [{
              add_on_id: addon.id,
              name: addon.name,
              units: 1,
              unit_amount_cents: addon.amount_cents
            }],
            timestamp: Time.current.to_i,
            skip_psp: false
          )

          if invoice_result.success?
            puts "    → Invoice created: #{invoice_result.invoice.number} (#{invoice_result.invoice.total_amount_cents / 100.0} #{CURRENCY})"
            created_count += 1
          else
            puts "    → Invoice failed: #{invoice_result.error}"
            failed_count += 1
          end
        end
      rescue ActiveRecord::RecordNotUnique
        puts "  ⚠ Customer #{i + 1}/#{CUSTOMER_COUNT}: Skipped (duplicate external_id)"
        skipped_count += 1
      rescue => e
        puts "  ✗ Customer #{i + 1}/#{CUSTOMER_COUNT}: Failed - #{e.message}"
        failed_count += 1
      end

      # Small delay to avoid hitting rate limits
      sleep(0.1) if i > 0 && (i % 10).zero?
    end

    puts "-" * 60
    puts "Seeding complete!"
    puts "  Created: #{created_count}"
    puts "  Failed: #{failed_count}"
    puts "  Skipped: #{skipped_count}"
  end

  desc "Create 100 customers with Stripe (dry run - no actual API calls)"
  task stripe_customers_dry_run: :environment do
    ORGANIZATION_NAME = ENV.fetch("SEED_ORGANIZATION_NAME", "Hooli")
    PAYMENT_PROVIDER_CODE = ENV.fetch("SEED_STRIPE_PROVIDER_CODE", nil)
    CUSTOMER_COUNT = ENV.fetch("SEED_CUSTOMER_COUNT", 100).to_i

    puts "DRY RUN - Would create #{CUSTOMER_COUNT} customers"
    puts "-" * 60

    organization = Organization.find_by!(name: ORGANIZATION_NAME)
    puts "✓ Organization: #{organization.name}"

    stripe_provider = if PAYMENT_PROVIDER_CODE.present?
      organization.stripe_payment_providers.find_by!(code: PAYMENT_PROVIDER_CODE)
    else
      organization.stripe_payment_providers.first
    end

    if stripe_provider
      puts "✓ Stripe Provider: #{stripe_provider.code}"
    else
      puts "✗ No Stripe provider found!"
      exit 1
    end

    addon = organization.add_ons.find_by(code: ENV.fetch("SEED_ADDON_CODE", "setup_fee"))
    if addon
      puts "✓ Add-on: #{addon.name}"
    else
      puts "✗ No add-on found with code: #{ENV.fetch("SEED_ADDON_CODE", "setup_fee")}"
      exit 1
    end

    puts "-" * 60
    puts "Sample customers that would be created:"
    5.times do |i|
      firstname = Faker::Name.first_name
      lastname = Faker::Name.last_name
      puts "  #{i + 1}. #{firstname} #{lastname} (seed_stripe_cust_#{SecureRandom.hex(8)})"
    end
    puts "  ... and #{CUSTOMER_COUNT - 5} more"
    puts ""
    puts "Run `rake seed:stripe_customers` to create customers for real."
  end
end

