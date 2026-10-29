# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::UpdateService do
  subject(:customers_service) { described_class.new(customer:, args: update_args) }

  let_it_be(:organization, refind: true) { create_default(:organization) }
  let_it_be(:billing_entity, refind: true) { create_default(:billing_entity) }
  let(:payment_provider_code) { "stripe_1" }

  describe "call" do
    let(:customer) do
      create(
        :customer,
        organization:,
        billing_entity:,
        payment_provider: "stripe",
        payment_provider_code:
      )
    end

    let(:external_id) { SecureRandom.uuid }

    let(:update_args) do
      {
        id: customer.id,
        name: "Updated customer name",
        firstname: "Updated customer firstname",
        lastname: "Updated customer lastname",
        customer_type: "individual",
        tax_identification_number: "2246",
        net_payment_term: 8,
        external_id:,
        shipping_address: {
          city: "Paris"
        },
        account_type: account_type,
        billing_configuration: {
          subscription_invoice_issuing_date_anchor: "current_period_end",
          subscription_invoice_issuing_date_adjustment: "keep_anchor"
        }
      }
    end

    let(:account_type) { "customer" }

    context "with a database uniqueness conflict" do
      subject(:result) { described_class.call(customer:, args: update_args) }

      let(:constraint) { "index_customers_on_external_id_and_organization_id" }
      let(:database_result) { instance_double(PG::Result, error_field: constraint) }
      let(:database_error) { PG::UniqueViolation.new("duplicate value") }
      let(:write_error) { ActiveRecord::RecordNotUnique.new("duplicate value") }

      before do
        allow(database_error).to receive(:result).and_return(database_result)
        allow(customer).to receive(:save!) { raise write_error, cause: database_error }
      end

      it "returns a validation error for an external ID collision" do
        original_attributes = customer.attributes

        expect(result.error.messages).to eq(external_id: ["value_already_exist"])
        expect(customer.reload.attributes).to eq(original_attributes)
        expect(SendWebhookJob).not_to have_been_enqueued.with("customer.updated", customer)
      end

      context "with another constraint" do
        let(:constraint) { "customers_pkey" }

        it "does not hide the database error" do
          expect { result }.to raise_error(ActiveRecord::RecordNotUnique)
        end
      end
    end

    context "when tax assignment fails" do
      let(:update_args) { super().merge(tax_codes: ["unknown-tax"]) }

      it "rolls back customer changes" do
        original_attributes = customer.attributes

        result = customers_service.call

        expect(result).to be_failure
        expect(customer.reload.attributes).to eq(original_attributes)
        expect(SendWebhookJob).not_to have_been_enqueued.with("customer.updated", customer)
      end
    end

    context "with invoice custom section codes" do
      let(:section) { create(:invoice_custom_section, organization:) }
      let(:update_args) { super().merge(invoice_custom_section_codes: [section.code]) }

      it "assigns sections by code" do
        result = customers_service.call

        expect(result).to be_success
        expect(customer.reload.manual_selected_invoice_custom_sections).to eq([section])
      end
    end

    it "updates a customer and calls SendWebhookJob" do
      result = customers_service.call
      updated_customer = result.customer
      expect(updated_customer.name).to eq(update_args[:name])
      expect(updated_customer.firstname).to eq(update_args[:firstname])
      expect(updated_customer.lastname).to eq(update_args[:lastname])
      expect(updated_customer.customer_type).to eq(update_args[:customer_type])
      expect(updated_customer.tax_identification_number).to eq(update_args[:tax_identification_number])
      expect(updated_customer.subscription_invoice_issuing_date_anchor).to eq("current_period_end")
      expect(updated_customer.subscription_invoice_issuing_date_adjustment).to eq("keep_anchor")

      shipping_address = update_args[:shipping_address]
      expect(updated_customer.shipping_city).to eq(shipping_address[:city])
      expect(SendWebhookJob).to have_been_enqueued.with("customer.updated", updated_customer)
    end

    it "produces an activity log" do
      described_class.call(customer:, args: update_args)

      expect(Utils::ActivityLog).to have_produced("customer.updated").after_commit.with(customer)
    end

    it "refreshes the invoices search terms when a searchable field changes" do
      expect { customers_service.call }
        .to have_enqueued_job_after_commit(Customers::RefreshInvoicesSearchTermsJob).with(customer.id)
    end

    context "when no searchable field changes" do
      let(:update_args) { {id: customer.id, net_payment_term: 8} }

      it "does not refresh the invoices search terms" do
        expect { customers_service.call }.not_to have_enqueued_job(Customers::RefreshInvoicesSearchTermsJob)
      end
    end

    context "with email containing unicode lookalike characters" do
      let(:update_args) do
        {
          id: customer.id,
          email: "hello@something\u2013other.com"
        }
      end

      it "sanitizes the email before saving" do
        result = customers_service.call
        expect(result.customer.email).to eq("hello@something-other.com")
      end
    end

    context "with a line break in the address" do
      let(:update_args) { {id: customer.id, address_line2: "Line A\nLine B"} }

      it "stores the line break" do
        result = customers_service.call

        expect(result).to be_success
        expect(customer.reload.address_line2).to eq("Line A\nLine B")
      end
    end

    context "with a tab in the address" do
      let(:update_args) { {id: customer.id, address_line2: "Floor 2\tSuite 4"} }

      it "stores the tab" do
        result = customers_service.call

        expect(result).to be_success
        expect(customer.reload.address_line2).to eq("Floor 2\tSuite 4")
      end
    end

    context "when updating the billing entity reference" do
      let(:billing_entity_2) { create(:billing_entity, organization:) }

      let(:update_args) do
        {
          id: customer.id,
          name: "Updated customer name",
          billing_entity_code: billing_entity_2.code
        }
      end

      it "updates the billing entity" do
        result = customers_service.call
        expect(result).to be_success
        expect(result.customer.billing_entity).to eq(billing_entity_2)
      end

      context "when billing entity is archived" do
        before { billing_entity_2.update!(archived_at: Time.current) }

        it "fails" do
          result = customers_service.call

          expect(result).to be_failure
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq("billing_entity")
        end
      end

      context "when customer is attached to a subscription" do
        before do
          create(:subscription, customer:)
        end

        it "updates the billing entity" do
          result = customers_service.call
          expect(result).to be_success
          expect(result.customer.billing_entity).to eq(billing_entity_2)
        end
      end
    end

    context "when updating account_type to partner" do
      let(:customer) do
        create(
          :customer,
          organization:,
          exclude_from_dunning_campaign: false,
          applied_dunning_campaign: dunning_campaign
        )
      end

      let(:dunning_campaign) { create(:dunning_campaign) }

      let(:organization) do
        create(:organization, premium_integrations: ["auto_dunning"])
      end

      let(:account_type) { "partner" }

      it "does not change the account_type" do
        result = customers_service.call

        updated_customer = result.customer
        expect(updated_customer.name).to eq(update_args[:name])
        expect(updated_customer).to be_customer_account
        expect(updated_customer).not_to be_exclude_from_dunning_campaign
        expect(updated_customer.applied_dunning_campaign).to eq dunning_campaign
      end
    end

    context "with premium features", :premium do
      let(:update_args) do
        {
          id: customer.id,
          name: "Updated customer name",
          timezone: "Europe/Paris",
          billing_configuration: {
            invoice_grace_period: 3
          },
          account_type:
        }
      end

      it "updates a customer" do
        result = customers_service.call

        updated_customer = result.customer
        expect(updated_customer.timezone).to eq("Europe/Paris")
        expect(updated_customer.invoice_grace_period).to eq(3)
      end

      context "when revenue_share feature is enabled and updates account_type to partner" do
        let(:organization) do
          create(:organization, premium_integrations: %w[revenue_share auto_dunning])
        end

        let(:customer) do
          create(
            :customer,
            organization:,
            exclude_from_dunning_campaign: false,
            applied_dunning_campaign: dunning_campaign
          )
        end

        let(:dunning_campaign) { create(:dunning_campaign) }

        let(:account_type) { "partner" }

        it "updates the customer as partner" do
          result = customers_service.call

          updated_customer = result.customer
          expect(updated_customer.name).to eq(update_args[:name])
          expect(updated_customer).to be_partner_account
          expect(updated_customer).to be_exclude_from_dunning_campaign
          expect(updated_customer.applied_dunning_campaign).to be_nil
        end

        context "when customer is attached to a subscription" do
          before do
            create(:subscription, customer:)
          end

          it "does not update the account_type" do
            result = customers_service.call

            updated_customer = result.customer
            expect(updated_customer).to be_customer_account
          end
        end
      end
    end

    context "with metadata" do
      let(:customer_metadata) { create(:customer_metadata, customer:) }
      let(:another_customer_metadata) { create(:customer_metadata, customer:, key: "test", value: "1") }
      let(:update_args) do
        {
          id: customer.id,
          name: "Updated customer name",
          metadata: [
            {
              id: customer_metadata.id,
              key: "new key",
              value: "new value",
              display_in_invoice: true
            },
            {
              key: "Added key",
              value: "Added value",
              display_in_invoice: true
            }
          ]
        }
      end

      before do
        customer_metadata
        another_customer_metadata
      end

      it "updates metadata" do
        result = customers_service.call

        metadata_keys = result.customer.metadata.pluck(:key)
        metadata_ids = result.customer.metadata.pluck(:id)

        expect(result.customer.metadata.count).to eq(2)
        expect(metadata_keys).to eq(["new key", "Added key"])
        expect(metadata_ids).to include(customer_metadata.id)
        expect(metadata_ids).not_to include(another_customer_metadata.id)
      end
    end

    context "with validation error" do
      let(:external_id) { nil }

      it "returns an error" do
        result = customers_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:external_id]).to eq(["value_is_mandatory"])
      end
    end

    context "when attached to a subscription" do
      let(:account_type) { "partner" }

      before do
        subscription = create(:subscription, customer:)
        customer.update!(currency: subscription.plan.amount_currency)
      end

      it "updates only the name" do
        result = customers_service.call

        updated_customer = result.customer
        expect(updated_customer.name).to eq("Updated customer name")
        expect(updated_customer.external_id).to eq(customer.external_id)
        expect(updated_customer.account_type).to eq customer.account_type
      end

      context "when updating the currency" do
        let(:update_args) do
          {
            id: customer.id,
            currency: "CAD"
          }
        end

        it "updates the currency" do
          result = customers_service.call

          expect(result).to be_success
          expect(result.customer.currency).to eq("CAD")
        end
      end
    end

    context "when updating payment provider" do
      let(:update_args) do
        {
          id: customer.id,
          name: "Updated customer name",
          external_id:,
          payment_provider: "stripe",
          payment_provider_code:
        }
      end

      before do
        create(:stripe_provider, organization: customer.organization, code: payment_provider_code)

        allow(PaymentProviderCustomers::UpdateService)
          .to receive(:call)
          .with(customer)
          .and_return(PaymentProviderCustomers::UpdateService::Result.new)
      end

      it "creates a payment provider customer" do
        result = customers_service.call
        expect(result).to be_success

        updated_customer = result.customer
        expect(updated_customer.payment_provider).to eq("stripe")
        expect(updated_customer.stripe_customer).to be_present
      end

      it "does not call payment provider customer update service" do
        customers_service.call
        expect(PaymentProviderCustomers::UpdateService).not_to have_received(:call).with(customer)
      end

      context "with provider customer id" do
        let(:update_args) do
          {
            id: customer.id,
            external_id: SecureRandom.uuid,
            name: "Foo Bar",
            organization_id: organization.id,
            payment_provider: "stripe",
            provider_customer: {provider_customer_id: "cus_12345"}
          }
        end

        it "calls payment provider customer update service" do
          customers_service.call
          expect(PaymentProviderCustomers::UpdateService).to have_received(:call).with(customer)
        end

        it "creates a payment provider customer" do
          result = customers_service.call

          expect(result).to be_success

          customer = result.customer
          expect(customer.id).to be_present
          expect(customer.payment_provider).to eq("stripe")
          expect(customer.stripe_customer).to be_present
          expect(customer.stripe_customer.provider_customer_id).to eq("cus_12345")
        end

        context "when removing a provider customer id" do
          let(:update_args) do
            {
              id: customer.id,
              external_id: SecureRandom.uuid,
              name: "Foo Bar",
              organization_id: organization.id,
              payment_provider: nil,
              provider_customer: {provider_customer_id: nil}
            }
          end

          let(:stripe_customer) { create(:stripe_customer, customer:) }

          before do
            stripe_customer
            customer.update!(payment_provider: "stripe")
          end

          it "discards the provider customer" do
            result = customers_service.call

            expect(result).to be_success

            result_customer = result.customer
            expect(result_customer.id).to eq(customer.id)
            expect(result_customer.payment_provider).to be_nil

            expect(stripe_customer.reload).to be_discarded
          end
        end
      end
    end

    context "when removing payment provider" do
      let(:stripe_provider) { create(:stripe_provider, organization:, code: payment_provider_code) }
      let(:customer) do
        create(
          :customer,
          organization:,
          billing_entity:,
          payment_provider: "stripe",
          payment_provider_code:
        )
      end
      let(:stripe_customer) { create(:stripe_customer, customer:, payment_provider: stripe_provider) }
      let(:payment_method) do
        create(:payment_method, customer:, payment_provider: stripe_provider, payment_provider_customer: stripe_customer)
      end

      let(:update_args) do
        {
          id: customer.id,
          organization_id: organization.id,
          payment_provider: nil,
          provider_customer: nil,
          payment_provider_code: nil
        }
      end

      before { payment_method }

      it "sets the customer parameters to nil" do
        result = customers_service.call

        expect(result).to be_success

        customer = result.customer
        expect(customer.payment_provider).to be_nil
        expect(customer.provider_customer).to be_nil
        expect(customer.payment_provider_code).to be_nil
      end

      it "discards the provider customer" do
        result = customers_service.call

        expect(result).to be_success
        expect(stripe_customer.reload).to be_discarded
      end

      it "discards the payment methods" do
        result = customers_service.call

        expect(result).to be_success
        expect(payment_method.reload).to be_discarded
      end

      context "when a non-nil payment_provider_code is still provided" do
        let(:update_args) do
          {
            id: customer.id,
            organization_id: organization.id,
            payment_provider: nil,
            provider_customer: nil,
            payment_provider_code:
          }
        end

        it "wipes out the payment_provider_code" do
          result = customers_service.call

          expect(result).to be_success
          expect(result.customer.payment_provider_code).to be_nil
        end
      end
    end

    context "when partialy updating", :premium do
      let(:stripe_customer) { create(:stripe_customer, customer:, provider_payment_methods: %w[sepa_debit]) }

      let(:update_args) do
        {
          id: customer.id,
          invoice_grace_period: 8
        }
      end

      before { stripe_customer }

      it "updates only the updated args" do
        result = customers_service.call

        expect(result).to be_success
        expect(result.customer.invoice_grace_period).to eq(update_args[:invoice_grace_period])

        expect(result.customer.stripe_customer.provider_payment_methods).to eq(%w[sepa_debit])
      end
    end

    context "when updating net payment term" do
      it "updates the net payment term of all draft invoices" do
        create(:invoice, :draft, customer:, net_payment_term: 30)
        create(:invoice, customer:, net_payment_term: 30)
        create(:invoice, :draft, customer:, net_payment_term: 30)

        result = customers_service.call

        expect(result).to be_success
        expect(result.customer.invoices.draft.pluck(:net_payment_term)).to eq([8, 8])
      end
    end

    context "when updating invoice_custom_sections" do
      let(:invoice_custom_sections) { create_list(:invoice_custom_section, 4, organization:) }

      before do
        create(:customer_applied_invoice_custom_section, organization:, billing_entity:, customer:, invoice_custom_section: invoice_custom_sections[0])
        create(:billing_entity_applied_invoice_custom_section, organization:, billing_entity:, invoice_custom_section: invoice_custom_sections[2])
        create(:billing_entity_applied_invoice_custom_section, organization:, billing_entity:, invoice_custom_section: invoice_custom_sections[3])
      end

      context "when customer is set to skip_invoice_custom_sections: true" do
        let(:update_args) do
          {
            id: customer.id,
            skip_invoice_custom_sections: true
          }
        end

        it "clears customer selected invoice custom sections" do
          result = customers_service.call
          expect(result).to be_success
          expect(customer.reload.selected_invoice_custom_sections).to be_empty
          expect(customer.applicable_invoice_custom_sections).to be_empty
        end
      end

      context "when setting to invoice custom sections that match with organization selected invoice custom sections" do
        let(:update_args) do
          {
            id: customer.id,
            configurable_invoice_custom_section_ids: []
          }
        end

        it "assigns organization sections to customer" do
          result = customers_service.call
          expect(result).to be_success
          expect(customer.reload.selected_invoice_custom_sections).to be_empty
          expect(customer.applicable_invoice_custom_sections.ids).to match_array(invoice_custom_sections[2..3].map(&:id))
        end
      end

      context "when setting custom invoice_custom_sections for the customer" do
        let(:update_args) do
          {
            id: customer.id,
            configurable_invoice_custom_section_ids: invoice_custom_sections[1..2].map(&:id)
          }
        end

        it "assigns customer sections" do
          result = customers_service.call
          expect(result).to be_success
          expect(customer.reload.selected_invoice_custom_sections.ids).to match_array(invoice_custom_sections[1..2].map(&:id))
        end
      end

      context "when setting custom invoice_custom_sections for the customer with skipped invoice_custom_sections" do
        let(:update_args) do
          {
            id: customer.id,
            configurable_invoice_custom_section_ids: invoice_custom_sections[1..2].map(&:id)
          }
        end

        before { customer.update!(skip_invoice_custom_sections: true) }

        it "updates skip_invoice_custom_sections to false" do
          result = customers_service.call
          expect(result).to be_success
          expect(customer.reload.skip_invoice_custom_sections).to be false
          expect(customer.selected_invoice_custom_sections.ids).to match_array(invoice_custom_sections[1..2].map(&:id))
        end
      end

      context "when sending both: skip_invoice_custom_sections and applicable_invoice_custom_section_ids" do
        let(:update_args) do
          {
            id: customer.id,
            skip_invoice_custom_sections: true,
            configurable_invoice_custom_section_ids: invoice_custom_sections[1..2].map(&:id)
          }
        end

        it "returns an error" do
          result = customers_service.call
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:invoice_custom_sections]).to include("skip_sections_and_selected_ids_sent_together")
        end
      end
    end

    context "when organization has eu tax management" do
      let(:tax_code) { "lago_eu_fr_standard" }
      let(:eu_tax_result) { Customers::EuAutoTaxesService::Result.new }

      before do
        create(:tax, organization:, code: "lago_eu_fr_standard", rate: 20.0)
        organization.update(eu_tax_management: true)

        eu_tax_result.tax_code = tax_code
        eu_tax_result.tax_codes = [tax_code]
        allow(Customers::EuAutoTaxesService).to receive(:call).and_return(eu_tax_result)
      end

      it "assigns the right tax to the customer" do
        result = customers_service.call

        expect(result).to be_success

        tax = result.customer.taxes.first
        expect(tax.code).to eq(tax_code)
      end

      context "when eu tax code is not applicable" do
        let(:eu_tax_result) { Customers::EuAutoTaxesService::Result.new.not_allowed_failure!(code: "") }

        it "does not apply tax" do
          result = customers_service.call

          expect(result).to be_success

          expect(result.customer.taxes).to eq([])
        end
      end
    end

    context "when the billing entity changes and entities have different EU tax settings" do
      let(:eu_billing_entity) { create(:billing_entity, organization:, country: "FR", eu_tax_management: true) }
      let(:other_eu_billing_entity) { create(:billing_entity, organization:, country: "DE", eu_tax_management: true) }
      let(:non_eu_billing_entity) { create(:billing_entity, organization:, country: "US", eu_tax_management: false) }

      let(:fr_tax) { create(:tax, organization:, code: "lago_eu_fr_standard", rate: 20.0) }
      let(:de_tax) { create(:tax, organization:, code: "lago_eu_de_standard", rate: 19.0) }

      let(:customer) { create(:customer, organization:, billing_entity: source_billing_entity, country: nil, zipcode: nil) }

      let(:update_args) { {id: customer.id, billing_entity_code: target_billing_entity.code} }

      before do
        fr_tax
        de_tax
        create(:customer_applied_tax, organization:, customer:, tax: applied_tax) if applied_tax
      end

      context "when moving from an EU entity to a non-EU entity" do
        let(:source_billing_entity) { eu_billing_entity }
        let(:target_billing_entity) { non_eu_billing_entity }
        let(:applied_tax) { fr_tax }

        it "resets the EU tax so the customer falls back to the billing entity" do
          result = customers_service.call

          expect(result).to be_success
          expect(result.customer.billing_entity).to eq(non_eu_billing_entity)
          expect(result.customer.taxes).to eq([])
        end
      end

      context "when moving from a non-EU entity to an EU entity" do
        let(:source_billing_entity) { non_eu_billing_entity }
        let(:target_billing_entity) { eu_billing_entity }
        let(:applied_tax) { nil }

        it "assigns the new billing entity EU tax" do
          result = customers_service.call

          expect(result).to be_success
          expect(result.customer.billing_entity).to eq(eu_billing_entity)
          expect(result.customer.taxes.pluck(:code)).to eq(["lago_eu_fr_standard"])
        end
      end

      context "when moving between two EU entities in different countries" do
        let(:source_billing_entity) { eu_billing_entity }
        let(:target_billing_entity) { other_eu_billing_entity }
        let(:applied_tax) { fr_tax }

        it "re-evaluates the EU tax against the new billing entity" do
          result = customers_service.call

          expect(result).to be_success
          expect(result.customer.billing_entity).to eq(other_eu_billing_entity)
          expect(result.customer.taxes.pluck(:code)).to eq(["lago_eu_de_standard"])
        end
      end

      context "when the new EU entity requires a VIES check" do
        let(:source_billing_entity) { eu_billing_entity }
        let(:target_billing_entity) { other_eu_billing_entity }
        let(:applied_tax) { fr_tax }

        let(:customer) do
          create(:customer, organization:, billing_entity: source_billing_entity, country: nil, zipcode: nil, tax_identification_number: "FR123456789")
        end

        it "resets the EU tax and schedules a VIES check for the new billing entity" do
          result = customers_service.call

          expect(result).to be_success
          expect(result.customer.taxes).to eq([])
          expect(customer.reload.pending_vies_check).to have_attributes(
            billing_entity: other_eu_billing_entity,
            tax_identification_number: "FR123456789"
          )
        end
      end

      context "when the billing entity does not change" do
        let(:source_billing_entity) { eu_billing_entity }
        let(:target_billing_entity) { eu_billing_entity }
        let(:applied_tax) { fr_tax }

        it "keeps the existing customer tax" do
          result = customers_service.call

          expect(result).to be_success
          expect(result.customer.taxes.pluck(:code)).to eq(["lago_eu_fr_standard"])
        end
      end
    end

    context "when a non EU customer without tax identification number has a custom tax" do
      let_it_be(:eu_billing_entity) { create(:billing_entity, organization:, country: "FR", eu_tax_management: true) }
      let_it_be(:exempt_tax) { create(:tax, organization:, code: "lago_eu_tax_exempt", rate: 0.0) }
      let_it_be(:custom_tax) { create(:tax, organization:, code: "uk_vat", rate: 20.0) }
      let(:customer) do
        create(:customer, organization:, billing_entity: eu_billing_entity, country: "GB", zipcode: "SW1A 1AA", tax_identification_number: nil)
      end

      before { create(:customer_applied_tax, organization:, customer:, tax: custom_tax) }

      context "when the name changes" do
        let(:update_args) { {id: customer.id, name: "New name"} }

        it "keeps the custom tax without refreshing draft invoices" do
          invoice = create(:invoice, :draft, organization:, customer:)
          result = customers_service.call

          expect(result).to be_success
          expect(result.customer.taxes.pluck(:code)).to eq(["uk_vat"])
          expect(invoice.reload.ready_to_be_refreshed).to be(false)
        end
      end

      context "when the customer also has the EU exemption" do
        let(:update_args) { {id: customer.id, zipcode: "EC1A 1BB"} }

        before { create(:customer_applied_tax, organization:, customer:, tax: exempt_tax) }

        it "removes the EU exemption" do
          result = customers_service.call

          expect(result).to be_success
          expect(result.customer.taxes.pluck(:code)).to eq(["uk_vat"])
        end
      end

      context "when the zipcode changes without tax codes" do
        let(:update_args) { {id: customer.id, zipcode: "EC1A 1BB"} }

        it "keeps the custom tax" do
          result = customers_service.call

          expect(result).to be_success
          expect(result.customer.taxes.pluck(:code)).to eq(["uk_vat"])
        end
      end

      context "when the customer moves to an EU country" do
        let(:update_args) { {id: customer.id, country: "DE", zipcode: "10115"} }

        before { create(:tax, organization:, code: "lago_eu_de_standard", rate: 19.0) }

        it "applies the EU country tax" do
          result = customers_service.call

          expect(result).to be_success
          expect(result.customer.taxes.pluck(:code)).to eq(["lago_eu_de_standard"])
        end
      end

      context "when a tax identification number is added" do
        let(:update_args) { {id: customer.id, tax_identification_number: "GB123456789"} }

        it "schedules a VIES check" do
          result = customers_service.call

          expect(result).to be_success
          expect(result.customer.pending_vies_check).to be_present
        end
      end

      context "when the custom tax is removed" do
        let(:update_args) { {id: customer.id, tax_codes: []} }

        it "applies the EU exemption" do
          result = customers_service.call

          expect(result).to be_success
          expect(result.customer.taxes.pluck(:code)).to eq(["lago_eu_tax_exempt"])
        end
      end

      context "when the customer leaves an EU country" do
        let(:customer) do
          create(:customer, organization:, billing_entity: eu_billing_entity, country: "FR", zipcode: "75001", tax_identification_number: nil)
        end
        let(:update_args) { {id: customer.id, country: "GB", zipcode: "SW1A 1AA"} }

        before { create(:customer_applied_tax, organization:, customer:, tax: create(:tax, organization:, code: "lago_eu_fr_standard", rate: 20.0)) }

        it "replaces the EU rate with the EU exemption" do
          result = customers_service.call

          expect(result).to be_success
          expect(result.customer.taxes.pluck(:code)).to eq(["lago_eu_tax_exempt"])
        end
      end

      context "when the exemption is sent with the custom tax" do
        let(:update_args) { {id: customer.id, tax_codes: %w[lago_eu_tax_exempt uk_vat]} }

        it "applies the custom tax only" do
          result = customers_service.call

          expect(result).to be_success
          expect(result.customer.taxes.pluck(:code)).to eq(["uk_vat"])
        end
      end
    end

    context "when dunning campaign data is provided" do
      let(:customer) do
        create(
          :customer,
          organization:,
          applied_dunning_campaign: dunning_campaign,
          last_dunning_campaign_attempt: 3,
          last_dunning_campaign_attempt_at: 2.days.ago
        )
      end
      let(:dunning_campaign) { create(:dunning_campaign) }

      let(:update_args) do
        {
          id: customer.id,
          applied_dunning_campaign_id: dunning_campaign.id,
          exclude_from_dunning_campaign: true
        }
      end

      it "does not update auto dunning config" do
        expect { customers_service.call }
          .to not_change(customer, :applied_dunning_campaign_id)
          .and not_change(customer, :exclude_from_dunning_campaign)
          .and not_change(customer, :last_dunning_campaign_attempt)
          .and not_change { customer.last_dunning_campaign_attempt_at.iso8601 }

        expect(customers_service.call).to be_success
      end

      context "with auto_dunning premium integration", :premium do
        let(:customer) do
          create(
            :customer,
            organization:,
            exclude_from_dunning_campaign: true,
            last_dunning_campaign_attempt: 3,
            last_dunning_campaign_attempt_at: 2.days.ago
          )
        end

        let(:organization) do
          create(:organization, premium_integrations: ["auto_dunning"])
        end

        let(:update_args) do
          {applied_dunning_campaign_id: dunning_campaign.id}
        end

        it "updates auto dunning config" do
          expect { customers_service.call }
            .to change(customer, :applied_dunning_campaign_id).to(dunning_campaign.id)
            .and change(customer, :exclude_from_dunning_campaign).to(false)
            .and change(customer, :last_dunning_campaign_attempt).to(0)
            .and change(customer, :last_dunning_campaign_attempt_at).to(nil)

          expect(customers_service.call).to be_success
        end

        context "with exclude from dunning campaign" do
          let(:customer) do
            create(
              :customer,
              organization:,
              applied_dunning_campaign: dunning_campaign,
              last_dunning_campaign_attempt: 3,
              last_dunning_campaign_attempt_at: 2.days.ago
            )
          end

          let(:update_args) do
            {exclude_from_dunning_campaign: true}
          end

          it "updates auto dunning config" do
            expect { customers_service.call }
              .to change(customer, :applied_dunning_campaign_id).to(nil)
              .and change(customer, :exclude_from_dunning_campaign).to(true)
              .and change(customer, :last_dunning_campaign_attempt).to(0)
              .and change(customer, :last_dunning_campaign_attempt_at).to(nil)

            expect(customers_service.call).to be_success
          end
        end

        context "with applied_dunning_campaign_id nil" do
          let(:customer) do
            create(
              :customer,
              organization:,
              applied_dunning_campaign: dunning_campaign,
              exclude_from_dunning_campaign: false,
              last_dunning_campaign_attempt: 3,
              last_dunning_campaign_attempt_at: 2.days.ago
            )
          end

          let(:update_args) { {applied_dunning_campaign_id: nil} }

          it "updates auto dunning config" do
            expect { customers_service.call }
              .to change(customer, :applied_dunning_campaign_id).to(nil)
              .and not_change(customer, :exclude_from_dunning_campaign)
              .and change(customer, :last_dunning_campaign_attempt).to(0)
              .and change(customer, :last_dunning_campaign_attempt_at).to(nil)

            expect(customers_service.call).to be_success
          end
        end

        context "when dunning campaign can not be found" do
          let(:customer) do
            create(
              :customer,
              organization:,
              applied_dunning_campaign: dunning_campaign,
              exclude_from_dunning_campaign: false,
              last_dunning_campaign_attempt: 3,
              last_dunning_campaign_attempt_at: 2.days.ago
            )
          end

          let(:update_args) { {applied_dunning_campaign_id: "not_found_id"} }

          it "does not update auto dunning config" do
            expect { customers_service.call }
              .to not_change(customer, :applied_dunning_campaign_id)
              .and not_change(customer, :exclude_from_dunning_campaign)
              .and not_change(customer, :last_dunning_campaign_attempt)
              .and not_change(customer, :last_dunning_campaign_attempt_at)

            result = customers_service.call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::NotFoundFailure)
            expect(result.error.error_code).to eq("dunning_campaign_not_found")
          end
        end
      end
    end

    context "with error details" do
      before do
        create(:error_detail, owner: customer, organization:, error_code: :tax_error)
      end

      context "when address fields change" do
        let(:update_args) { {id: customer.id, address_line1: "New Address"} }

        it "deletes the tax_error error_details" do
          result = customers_service.call

          expect(result).to be_success
          expect(customer.reload.error_details.count).to be_zero
        end
      end

      context "when non-address fields change" do
        let(:update_args) { {id: customer.id, name: "New Name"} }

        it "does not discard tax_error error_details" do
          result = customers_service.call

          expect(result).to be_success
          expect(customer.reload.error_details.count).to eq(1)
        end
      end
    end
  end
end
