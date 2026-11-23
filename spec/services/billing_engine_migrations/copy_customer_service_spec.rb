# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::CopyCustomerService do
  subject(:result) { described_class.call(migration:, customer:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:shadow_organization) { create(:shadow_organization) }
  let_it_be(:billing_entity) { organization.default_billing_entity }

  let(:shadow_entity_code) { billing_entity.code }
  let(:migration) { create(:billing_engine_migration, organization:, shadow_organization:) }

  let(:customer) do
    create(:customer, :with_shipping_address, organization:, billing_entity:, timezone: "America/Los_Angeles")
  end

  before { create(:billing_entity, organization: shadow_organization, code: shadow_entity_code, email_settings: []) }

  it "creates the customer in the shadow organization with the allow-listed attributes" do
    expect { result }.to change { shadow_organization.customers.count }.by(1)

    expect(result).to be_success
    expect(result.customer).to have_attributes(
      organization: shadow_organization,
      external_id: customer.external_id,
      name: customer.name,
      firstname: customer.firstname,
      lastname: customer.lastname,
      email: customer.email,
      phone: customer.phone,
      url: customer.url,
      legal_name: customer.legal_name,
      legal_number: customer.legal_number,
      tax_identification_number: customer.tax_identification_number,
      address_line1: customer.address_line1,
      address_line2: customer.address_line2,
      city: customer.city,
      state: customer.state,
      zipcode: customer.zipcode,
      country: customer.country,
      currency: customer.currency,
      shipping_address_line1: customer.shipping_address_line1,
      shipping_address_line2: customer.shipping_address_line2,
      shipping_city: customer.shipping_city,
      shipping_state: customer.shipping_state,
      shipping_zipcode: customer.shipping_zipcode,
      shipping_country: customer.shipping_country
    )
    expect(result.customer.billing_entity.code).to eq(billing_entity.code)
    expect(result.customer.billing_entity).not_to eq(shadow_organization.default_billing_entity)
  end

  context "when the shadow organization has no billing entity with the code of the V1 default" do
    let(:shadow_entity_code) { "other_code" }

    it "puts the shadow customer on the shadow default billing entity" do
      expect(result).to be_success
      expect(result.customer.billing_entity).to eq(shadow_organization.default_billing_entity)
    end
  end

  context "when the customer is on another billing entity than the default one" do
    let(:other_entity) { create(:billing_entity, organization:) }
    let(:shadow_entity_code) { other_entity.code }
    let(:customer) { create(:customer, organization:, billing_entity: other_entity) }

    it "puts the shadow customer on the shadow billing entity with the same code" do
      expect(result).to be_success
      expect(result.customer.billing_entity.code).to eq(other_entity.code)
      expect(result.customer.billing_entity).not_to eq(shadow_organization.default_billing_entity)
    end
  end

  context "when the customer has a payment provider, metadata and taxes" do
    let(:customer) { create(:customer, :with_stripe_payment_provider, organization:, billing_entity:) }

    before do
      create(:customer_metadata, customer:)
      create(:customer_applied_tax, customer:, tax: create(:tax, organization:))
    end

    it "does not copy them" do
      expect(result.customer.payment_provider).to be_nil
      expect(result.customer.payment_provider_code).to be_nil
      expect(result.customer.payment_provider_customers).to be_empty
      expect(result.customer.metadata).to be_empty
      expect(result.customer.taxes).to be_empty
    end
  end

  context "when the shadow organization already has the customer" do
    let(:shadow_customer) { create(:customer, organization: shadow_organization, external_id: customer.external_id) }

    before { shadow_customer }

    it "updates it to the customer attributes without creating another one" do
      expect { result }.not_to change { shadow_organization.customers.count }

      expect(result.customer).to eq(shadow_customer)
      expect(result.customer).to have_attributes(name: customer.name, email: customer.email, address_line1: customer.address_line1)
    end
  end

  context "when the shadow customer was copied before", :premium do
    let(:other_entity) { create(:billing_entity, organization:) }
    let(:shadow_customer) { shadow_organization.customers.find_by(external_id: customer.external_id) }

    before do
      described_class.call(migration:, customer:)
      create(:billing_entity, organization: shadow_organization, code: other_entity.code, email_settings: [])
      allow(Customers::UpdateService).to receive(:call!).and_call_original
    end

    it "returns it without writing when nothing changed" do
      expect(result.customer).to eq(shadow_customer)
      expect(Customers::UpdateService).not_to have_received(:call!)
    end

    context "when the customer has a blank attribute that the shadow customer holds as nil" do
      before do
        customer.update_column(:phone, "")
        shadow_customer.update_column(:phone, nil)
      end

      it "does not rewrite the shadow customer" do
        expect(result.customer.phone).to be_nil
        expect(Customers::UpdateService).not_to have_received(:call!)
      end
    end

    context "when the customer email was stored before its normalizer existed" do
      before { Customer.where(id: customer.id).update_all(["email = ?", " #{customer.email} "]) }

      it "does not rewrite the shadow customer" do
        expect(result.customer.email).to eq(customer.email)
        expect(Customers::UpdateService).not_to have_received(:call!)
      end
    end

    context "when copied attributes of the customer changed" do
      before do
        customer.update!(name: "New name", address_line2: nil, shipping_city: "Lyon", billing_entity: other_entity)
        create(:customer_metadata, customer:)
        create(:customer_applied_tax, customer:, tax: create(:tax, organization:))
      end

      it "updates the shadow customer with the changed attributes only" do
        expect(result).to be_success
        expect(Customers::UpdateService).to have_received(:call!).with(
          customer: shadow_customer,
          args: {name: "New name", address_line2: nil, billing_entity_code: other_entity.code, shipping_address: {city: "Lyon"}}
        )
        expect(result.customer).to have_attributes(id: shadow_customer.id, name: "New name", address_line2: nil, shipping_city: "Lyon")
        expect(result.customer.billing_entity.code).to eq(other_entity.code)
        expect(result.customer.metadata).to be_empty
        expect(result.customer.taxes).to be_empty
      end
    end

    context "when the shadow organization has no billing entity with the new code" do
      let(:unknown_entity) { create(:billing_entity, organization:) }

      before { customer.update!(name: "New name", billing_entity: unknown_entity) }

      it "returns the failure and leaves the shadow customer unchanged" do
        expect { result }.not_to change { shadow_customer.reload.name }

        expect(result).to be_failure
        expect(result.error.error_code).to eq("billing_entity_not_found")
      end
    end
  end

  context "without a premium license, when the customer has a timezone" do
    before do
      described_class.call(migration:, customer:)
      allow(Customers::UpdateService).to receive(:call!).and_call_original
    end

    it "leaves the timezone out so that the next copy writes nothing" do
      expect(result.customer.timezone).to be_nil
      expect(Customers::UpdateService).not_to have_received(:call!)
    end
  end

  context "when the customer changed since it was loaded" do
    before { Customer.find(customer.id).update!(name: "Newer name") }

    it "copies the latest committed attributes" do
      expect(result.customer.name).to eq("Newer name")
    end
  end

  context "when the customer was deleted since it was loaded" do
    before { Customer.find(customer.id).discard! }

    it "returns a not found failure and creates nothing" do
      expect { result }.not_to change { shadow_organization.customers.count }

      expect(result).to be_failure
      expect(result.error.error_code).to eq("customer_not_found")
    end
  end

  context "when copies of the customer run concurrently" do
    before { allow(Customers::LockService).to receive(:call).and_call_original }

    it "serializes them on a session lock of the customer" do
      result

      expect(Customers::LockService).to have_received(:call).with(customer:, scope: :shadow_copy, transaction: false)
    end
  end

  context "when another copy of the customer holds the lock" do
    before do
      allow(Customers::LockService).to receive(:call).and_raise(BaseLockService::FailedToAcquireLock, "Failed to acquire lock")
    end

    it "raises so that the job retries" do
      expect { result }.to raise_error(BaseLockService::FailedToAcquireLock)
    end
  end

  context "when the customer timezone is inherited from its billing entity", :premium do
    let(:paris_entity) { create(:billing_entity, organization:, timezone: "Europe/Paris") }
    let(:shadow_entity_code) { paris_entity.code }
    let(:customer) { create(:customer, organization:, billing_entity: paris_entity, timezone: nil) }

    it "gives the shadow customer the same timezone" do
      expect(result.customer.applicable_timezone).to eq("Europe/Paris")
    end
  end

  context "when the customer is created concurrently" do
    let(:taken_failure) do
      BaseService::Result.new.single_validation_failure!(field: :external_id, error_code: "value_already_exist")
    end

    let(:concurrent_customer) do
      create(:customer, organization: shadow_organization, external_id: customer.external_id)
    end

    before do
      allow(Customers::CreateService).to receive(:call) do
        concurrent_customer
        taken_failure
      end
    end

    it "updates and returns the customer created by the other writer" do
      expect(result).to be_success
      expect(result.customer).to eq(concurrent_customer)
      expect(result.customer.name).to eq(customer.name)
    end
  end

  context "when the external id is reported as taken but no shadow customer has it" do
    before do
      allow(Customers::CreateService).to receive(:call).and_return(
        BaseService::Result.new.single_validation_failure!(field: :external_id, error_code: "value_already_exist")
      )
    end

    it "returns the failure" do
      expect(result).to be_failure
      expect(result.error.messages).to eq(external_id: ["value_already_exist"])
      expect(result.customer).to be_nil
    end
  end

  context "when the customer creation fails for another reason" do
    before do
      allow(Customers::CreateService).to receive(:call).and_return(
        BaseService::Result.new.single_validation_failure!(field: :external_id, error_code: "value_is_invalid")
      )
    end

    it "returns the failure" do
      expect(result).to be_failure
      expect(result.error.messages).to eq(external_id: ["value_is_invalid"])
    end
  end

  context "when the migration is not shadowing" do
    let(:migration) { create(:billing_engine_migration, organization:, shadow_organization:, status: "paused") }

    it "does nothing" do
      expect { result }.not_to change { shadow_organization.customers.count }

      expect(result).to be_success
      expect(result.customer).to be_nil
    end
  end

  context "when the customer belongs to another organization" do
    let(:customer) { create(:customer, organization: create(:organization)) }

    it "does nothing" do
      expect { result }.not_to change { shadow_organization.customers.count }

      expect(result).to be_success
      expect(result.customer).to be_nil
    end
  end

  context "when a billing entity of the shadow organization sends invoice emails" do
    let(:shadow_customer) { create(:customer, organization: shadow_organization, external_id: customer.external_id) }

    before do
      shadow_customer
      create(:billing_entity, organization: shadow_organization, email_settings: ["invoice.finalized"])
    end

    it "returns a failure without creating or returning the shadow customer" do
      expect { result }.not_to change { shadow_organization.customers.count }

      expect(result).to be_failure
      expect(result.error.code).to eq("shadow_organization_not_isolated")
      expect(result.customer).to be_nil
    end
  end

  context "when the shadow organization has no billing entity with the code of the customer" do
    let(:shadow_entity_code) { "unknown_entity" }
    let(:customer) { create(:customer, organization:, billing_entity: create(:billing_entity, organization:)) }

    it "returns the failure and creates nothing" do
      expect { result }.not_to change { shadow_organization.customers.count }

      expect(result).to be_failure
      expect(result.customer).to be_nil
      expect(result.error.error_code).to eq("billing_entity_not_found")
    end
  end
end
