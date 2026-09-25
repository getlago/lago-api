# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::Taxes::CreditNotes::Payloads::BasePayload do
  {
    anrok: Integrations::Aggregator::Taxes::CreditNotes::Payloads::Anrok,
    avalara: Integrations::Aggregator::Taxes::CreditNotes::Payloads::Avalara
  }.each do |provider, payload_class|
    context "with #{provider}" do
      subject(:payload) { payload_class.new(integration:, customer:, integration_customer:, credit_note:).body.first }

      let(:credit_note) { create(:credit_note, invoice:, customer:) }
      let(:invoice) { create(:invoice) }
      let(:customer) { invoice.customer }
      let(:integration) { create(:"#{provider}_integration", organization: customer.organization) }
      let(:integration_customer) { create(:"#{provider}_customer", integration:, customer:) }
      let(:reloaded_payload) do
        payload_class.new(integration:, customer:, integration_customer:, credit_note: CreditNote.find(credit_note.id)).body.first
      end
      let(:charge) { create(:standard_charge, organization: customer.organization) }
      let(:other_charge) { create(:standard_charge, organization: customer.organization, billable_metric: charge.billable_metric) }
      let(:fee) { create(:charge_fee, invoice:, charge:) }
      let(:other_fee) { create(:charge_fee, invoice:, charge: other_charge) }
      let(:created_at) { Time.current.change(usec: 0) }
      let(:first_item) do
        create(:credit_note_item, credit_note:, fee:, amount_cents: 100, precise_amount_cents: 100,
          created_at:, id: "00000000-0000-4000-8000-000000000001")
      end
      let(:second_item) do
        create(:credit_note_item, credit_note:, fee: other_fee, amount_cents: 100, precise_amount_cents: 100,
          created_at:, id: "00000000-0000-4000-8000-000000000002")
      end

      before do
        second_item
        first_item
      end

      it "orders equal timestamps by item ID and distinguishes charges sharing a metric" do
        expect(payload.fetch("fees").map { |item| item.fetch("item_id") }).to eq([charge.id, other_charge.id])
      end

      it "keeps identifiers and ordering unchanged when reporting the credit note again" do
        expect(reloaded_payload).to eq(payload)
      end

      context "when only one charge fee is credited" do
        let(:second_item) { nil }

        it "uses the charge ID even without grouping" do
          expect(payload.fetch("id")).to eq("cn_#{credit_note.id}")
          expect(payload.fetch("fees").map { |item| item.fetch("item_id") }).to eq([charge.id])
        end

        context "when the invoice has other fees for the charge" do
          let(:other_charge) { charge }

          before { other_fee }

          it "keeps the charge identifier for a partial credit of a grouped invoice line" do
            expect(payload.fetch("fees").map { |item| item.fetch("item_id") }).to eq([charge.id])
          end
        end
      end
    end
  end
end
