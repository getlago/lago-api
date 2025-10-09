# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::UpdateService do
  subject(:customers_service) { described_class.new(customer:, args: update_args) }

  let(:billing_entity) { create(:billing_entity) }
  let(:organization) { billing_entity.organization }
  let(:payment_provider_code) { "stripe_1" }

  describe "update" do
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
        account_type: account_type
      }
    end

    let(:account_type) { "customer" }

    it "updates a customer and calls SendWebhookJob" do
      allow(SendWebhookJob).to receive(:perform_later)

      result = customers_service.call
      updated_customer = result.customer
      aggregate_failures do
        expect(updated_customer.name).to eq(update_args[:name])
        expect(updated_customer.firstname).to eq(update_args[:firstname])
        expect(updated_customer.lastname).to eq(update_args[:lastname])
        expect(updated_customer.customer_type).to eq(update_args[:customer_type])
        expect(updated_customer.tax_identification_number).to eq(update_args[:tax_identification_number])

        shipping_address = update_args[:shipping_address]
        expect(updated_customer.shipping_city).to eq(shipping_address[:city])
        expect(SendWebhookJob).to have_received(:perform_later).with("customer.updated", updated_customer)
      end
    end

    it "produces an activity log" do
      described_class.call(customer:, args: update_args)

      expect(Utils::ActivityLog).to have_produced("customer.updated").after_commit.with(customer)
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

        it "does not update the billing entity" do
          result = customers_service.call
          expect(result).to be_success
          expect(result.customer.billing_entity).to eq(billing_entity)
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

    context "with premium features" do
      around { |test| lago_premium!(&test) }

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
        aggregate_failures do
          expect(updated_customer.timezone).to eq("Europe/Paris")

          billing = update_args[:billing_configuration]
          expect(updated_customer.invoice_grace_period).to eq(billing[:invoice_grace_period])
        end
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

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:external_id]).to eq(["value_is_mandatory"])
        end
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

        it "fails" do
          result = customers_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages.keys).to include(:currency)
            expect(result.error.messages[:currency]).to include("currencies_does_not_match")
          end
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
          .and_return(BaseService::Result.new)
      end

      it "creates a payment provider customer" do
        result = customers_service.call
        expect(result).to be_success

        updated_customer = result.customer
        aggregate_failures do
          expect(updated_customer.payment_provider).to eq("stripe")
          expect(updated_customer.stripe_customer).to be_present
        end
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

          aggregate_failures do
            expect(result).to be_success

            customer = result.customer
            expect(customer.id).to be_present
            expect(customer.payment_provider).to eq("stripe")
            expect(customer.stripe_customer).to be_present
            expect(customer.stripe_customer.provider_customer_id).to eq("cus_12345")
          end
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

          it "removes the provider customer id" do
            result = customers_service.call

            aggregate_failures do
              expect(result).to be_success

              customer = result.customer
              expect(customer.id).to eq(customer.id)
              expect(customer.payment_provider).to be_nil

              expect(customer.stripe_customer).to eq(stripe_customer)
              expect(customer.stripe_customer.provider_customer_id).to be_nil
            end
          end
        end
      end
    end

    context "when partialy updating" do
      let(:stripe_customer) { create(:stripe_customer, customer:, provider_payment_methods: %w[sepa_debit]) }

      let(:update_args) do
        {
          id: customer.id,
          invoice_grace_period: 8
        }
      end

      around { |test| lago_premium!(&test) }
      before { stripe_customer }

      it "updates only the updated args" do
        result = customers_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.customer.invoice_grace_period).to eq(update_args[:invoice_grace_period])

          expect(result.customer.stripe_customer.provider_payment_methods).to eq(%w[sepa_debit])
        end
      end
    end

    context "when updating net payment term" do
      it "updates the net payment term of all draft invoices" do
        create(:invoice, :draft, customer:, net_payment_term: 30)
        create(:invoice, customer:, net_payment_term: 30)
        create(:invoice, :draft, customer:, net_payment_term: 30)

        result = customers_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.customer.invoices.draft.pluck(:net_payment_term)).to eq([8, 8])
        end
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
        allow(Customers::EuAutoTaxesService).to receive(:call).and_return(eu_tax_result)
      end

      it "assigns the right tax to the customer" do
        result = customers_service.call

        aggregate_failures do
          expect(result).to be_success

          tax = result.customer.taxes.first
          expect(tax.code).to eq(tax_code)
        end
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

      context "with auto_dunning premium integration" do
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

        around { |test| lago_premium!(&test) }

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
  end
end
