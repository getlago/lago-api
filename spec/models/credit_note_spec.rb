# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNote do
  subject(:credit_note) do
    create :credit_note, credit_amount_cents: 11000, total_amount_cents: 11000, taxes_amount_cents: 1000,
      taxes_rate: 10.0, precise_taxes_amount_cents: 1000
  end

  let(:item) { create(:credit_note_item, credit_note:, precise_amount_cents: 10000, amount_cents: 1000) }

  it_behaves_like "paper_trail traceable"

  it { is_expected.to belong_to(:organization) }
  it { is_expected.to have_one(:metadata).class_name("Metadata::ItemMetadata").dependent(:destroy) }
  it { is_expected.to have_many(:integration_resources) }
  it { is_expected.to have_many(:error_details) }

  describe "Clickhouse associations", clickhouse: true do
    it { is_expected.to have_many(:activity_logs).class_name("Clickhouse::ActivityLog") }
  end

  describe "sequential_id" do
    let(:invoice) { create(:invoice) }
    let(:customer) { invoice.customer }
    let(:credit_note) { build(:credit_note, invoice:, customer:) }

    it "assigns a sequential_id is present" do
      credit_note.save

      aggregate_failures do
        expect(credit_note).to be_valid
        expect(credit_note.sequential_id).to eq(1)
      end
    end

    context "when sequential_id is present" do
      before { credit_note.sequential_id = 3 }

      it "does not replace the sequential_id" do
        credit_note.save

        aggregate_failures do
          expect(credit_note).to be_valid
          expect(credit_note.sequential_id).to eq(3)
        end
      end
    end

    context "when credit note already exists" do
      before do
        create(:credit_note, invoice:, sequential_id: 5)
      end

      it "takes the next available id" do
        credit_note.save!

        aggregate_failures do
          expect(credit_note).to be_valid
          expect(credit_note.sequential_id).to eq(6)
        end
      end
    end

    context "with credit note on other invoice" do
      before do
        create(:credit_note, sequential_id: 1)
      end

      it "scopes the sequence to the invoice" do
        credit_note.save

        aggregate_failures do
          expect(credit_note).to be_valid
          expect(credit_note.sequential_id).to eq(1)
        end
      end
    end
  end

  describe "number" do
    let(:invoice) { create(:invoice, number: "CUST-001") }
    let(:customer) { invoice.customer }
    let(:credit_note) { build(:credit_note, invoice:, customer:) }

    it "generates the credit_note_number" do
      credit_note.save

      expect(credit_note.number).to eq("CUST-001-CN001")
    end
  end

  describe "#xml_url" do
    before do
      credit_note.xml_file.attach(
        io: StringIO.new(File.read(Rails.root.join("spec/fixtures/blank.xml"))),
        filename: "credit_note.xml",
        content_type: "application/xml"
      )
    end

    it "returns the xml file url" do
      xml_url = credit_note.xml_url

      expect(xml_url).to be_present
      expect(xml_url).to include(ENV["LAGO_API_URL"])
    end
  end

  describe "#currency" do
    let(:credit_note) { build(:credit_note, total_amount_currency: "JPY") }

    it { expect(credit_note.currency).to eq("JPY") }
  end

  describe "#credited?" do
    let(:credit_note) { build(:credit_note, credit_amount_cents: 0) }

    it { expect(credit_note).not_to be_credited }

    context "when credit amount is present" do
      let(:credit_note) { build(:credit_note, credit_amount_cents: 10) }

      it { expect(credit_note).to be_credited }
    end
  end

  describe "#refunded?" do
    let(:credit_note) { build(:credit_note) }

    it { expect(credit_note).not_to be_refunded }
  end

  describe "#refund_amount_cents" do
    let(:credit_note) { build(:credit_note) }

    it { expect(credit_note.refund_amount_cents).to be_zero }
  end

  describe "#subscription_ids" do
    let(:invoice) { credit_note.invoice }
    let(:subscription_fee) { create(:fee, invoice:) }
    let(:credit_note_item1) do
      create(:credit_note_item, credit_note:, fee: subscription_fee)
    end

    let(:charge_fee) { create(:charge_fee, invoice:) }
    let(:credit_note_item2) do
      create(:credit_note_item, credit_note:, fee: charge_fee)
    end

    before do
      credit_note_item1
      credit_note_item2
    end

    it "returns the list of subscription ids" do
      expect(credit_note.subscription_ids).to contain_exactly(
        subscription_fee.subscription_id,
        charge_fee.subscription_id
      )
    end

    context "with add_on fee" do
      let(:add_on_fee) { create(:add_on_fee, invoice:) }
      let(:credit_note_item3) do
        create(:credit_note_item, credit_note:, fee: add_on_fee)
      end

      before { credit_note_item3 }

      it "returns an empty subscription id" do
        expect(credit_note.subscription_ids).to include(
          subscription_fee.subscription_id,
          charge_fee.subscription_id,
          nil
        )
      end
    end

    describe "#subscription_item" do
      let(:invoice) { credit_note.invoice }
      let(:subscription_fee) { create(:fee, invoice:) }
      let(:credit_note_item1) do
        create(:credit_note_item, credit_note:, fee: subscription_fee)
      end

      let(:subscription) { subscription_fee.subscription }
      let(:charge_fee) { create(:charge_fee, invoice:, subscription:) }
      let(:credit_note_item2) do
        create(:credit_note_item, credit_note:, fee: charge_fee)
      end
      let(:fixed_charge_fee) { create(:fixed_charge_fee, invoice:, subscription:) }
      let(:credit_note_item3) do
        create(:credit_note_item, credit_note:, fee: fixed_charge_fee)
      end

      before do
        credit_note_item1
        credit_note_item2
        credit_note_item3
      end

      it "returns the item for the subscription fee" do
        expect(credit_note.subscription_item(subscription.id)).to eq(credit_note_item1)
      end

      context "when subscription id does not match an existing fee" do
        let(:missing_subscription) { create(:subscription) }

        it "returns a new fee" do
          fee = credit_note.subscription_item(missing_subscription.id)

          expect(fee).to be_new_record
        end
      end
    end

    describe "#subscription_charge_items" do
      let(:invoice) { credit_note.invoice }
      let(:subscription_fee) { create(:fee, invoice:) }
      let(:credit_note_item1) do
        create(:credit_note_item, credit_note:, fee: subscription_fee)
      end

      let(:subscription) { subscription_fee.subscription }

      let(:charge_fee) { create(:charge_fee, invoice:, subscription:) }
      let(:credit_note_item2) do
        create(:credit_note_item, credit_note:, fee: charge_fee)
      end

      let(:fixed_charge_fee) { create(:fixed_charge_fee, invoice:, subscription:) }
      let(:credit_note_item3) do
        create(:credit_note_item, credit_note:, fee: fixed_charge_fee)
      end

      before do
        credit_note_item1
        credit_note_item2
        credit_note_item3
      end

      it "returns the item for the charge fee" do
        expect(credit_note.subscription_charge_items(subscription.id)).to eq([credit_note_item2])
      end
    end

    describe "#subscription_fixed_charge_items" do
      let(:invoice) { credit_note.invoice }
      let(:subscription_fee) { create(:fee, invoice:) }
      let(:credit_note_item1) do
        create(:credit_note_item, credit_note:, fee: subscription_fee)
      end

      let(:subscription) { subscription_fee.subscription }

      let(:charge_fee) { create(:charge_fee, invoice:, subscription:) }
      let(:credit_note_item2) do
        create(:credit_note_item, credit_note:, fee: charge_fee)
      end

      let(:fixed_charge_fee) { create(:fixed_charge_fee, invoice:, subscription:) }
      let(:credit_note_item3) do
        create(:credit_note_item, credit_note:, fee: fixed_charge_fee)
      end

      before do
        credit_note_item1
        credit_note_item2
        credit_note_item3
      end

      it "returns the item for the fixed charge fee" do
        expect(credit_note.subscription_fixed_charge_items(subscription.id)).to eq([credit_note_item3])
      end
    end
  end

  describe "#add_on_items" do
    let(:invoice) { credit_note.invoice }
    let(:add_on) { create(:add_on, organization: credit_note.organization) }
    let(:applied_add_on) { create(:applied_add_on, add_on:) }
    let(:credit_note_item) { create(:credit_note_item, credit_note:, fee: add_on_fee) }
    let(:add_on_fee) { create(:add_on_fee, invoice:, applied_add_on:) }

    before { credit_note_item }

    it "returns items of the add-on" do
      expect(credit_note.add_on_items).to eq([credit_note_item])
    end
  end

  describe "#voidable?" do
    let(:credit_note) { create(:credit_note, balance_amount_cents:, credit_status:) }
    let(:balance_amount_cents) { 10 }
    let(:credit_status) { :available }

    it { expect(credit_note).to be_voidable }

    context "when balance is consumed" do
      let(:balance_amount_cents) { 0 }

      it { expect(credit_note).not_to be_voidable }
    end

    context "when already voided" do
      let(:credit_status) { :voided }

      it { expect(credit_note).not_to be_voidable }
    end
  end

  context "when calculating depends on related items" do
    before do
      item
      credit_note.reload
    end

    describe "#sub_total_excluding_taxes_amount_cents" do
      it "returs the total amount without the taxes" do
        expect(credit_note.sub_total_excluding_taxes_amount_cents)
          .to eq(credit_note.items.sum(&:precise_amount_cents) - credit_note.precise_coupons_adjustment_amount_cents)
      end
    end

    describe "#precise_total" do
      it "returns the total precise amount including precise taxes" do
        expect(credit_note.precise_total).to eq(11000)
      end
    end
  end

  describe "#taxes_rounding_adjustment" do
    it "returns the difference between taxes and precise taxes" do
      expect(credit_note.taxes_rounding_adjustment).to eq(0)
    end
  end

  describe "#rounding_adjustment" do
    it "returns the difference between credit note total and credit note precise total" do
      expect(credit_note.taxes_rounding_adjustment).to eq(0)
    end
  end

  describe "#should_sync_credit_note?" do
    subject(:method_call) { credit_note.should_sync_credit_note? }

    let(:credit_note) { create(:credit_note, customer:, organization:, status:) }
    let(:organization) { create(:organization) }

    context "when credit note is not finalized" do
      let(:status) { :draft }

      context "without integration customer" do
        let(:customer) { create(:customer, organization:) }

        it "returns false" do
          expect(method_call).to eq(false)
        end
      end

      context "with integration customer" do
        let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }
        let(:integration) { create(:netsuite_integration, organization:, sync_credit_notes:) }
        let(:customer) { create(:customer, organization:) }

        before { integration_customer }

        context "when sync credit notes is true" do
          let(:sync_credit_notes) { true }

          it "returns false" do
            expect(method_call).to eq(false)
          end
        end

        context "when sync credit notes is false" do
          let(:sync_credit_notes) { false }

          it "returns false" do
            expect(method_call).to eq(false)
          end
        end
      end
    end

    context "when credit note is finalized" do
      let(:status) { :finalized }

      context "without integration customer" do
        let(:customer) { create(:customer, organization:) }

        it "returns false" do
          expect(method_call).to eq(false)
        end
      end

      context "with integration customer" do
        let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }
        let(:integration) { create(:netsuite_integration, organization:, sync_credit_notes:) }
        let(:customer) { create(:customer, organization:) }

        before { integration_customer }

        context "when sync credit notes is true" do
          let(:sync_credit_notes) { true }

          it "returns true" do
            expect(method_call).to eq(true)
          end
        end

        context "when sync credit notes is false" do
          let(:sync_credit_notes) { false }

          it "returns false" do
            expect(method_call).to eq(false)
          end
        end
      end
    end
  end

  context "when taxes are not precise" do
    subject(:credit_note) do
      create :credit_note, credit_amount_cents: 8200, total_amount_cents: 8200, taxes_amount_cents: 1367,
        taxes_rate: 20.0, precise_taxes_amount_cents: 1366.6
    end

    let(:item) { create(:credit_note_item, credit_note:, precise_amount_cents: 6833, amount_cents: 6833) }

    before do
      item
      credit_note.reload
    end

    describe "#precise_total" do
      it "returns the total precise amount including precise taxes" do
        expect(credit_note.precise_total).to eq(8199.6)
      end
    end

    describe "#taxes_rounding_adjustment" do
      it "returns the difference between taxes and precise taxes" do
        expect(credit_note.taxes_rounding_adjustment).to eq(0.4)
      end
    end

    describe "#rounding_adjustment" do
      it "returns the difference between credit note total and credit note precise total" do
        expect(credit_note.taxes_rounding_adjustment).to eq(0.4)
      end
    end
  end

  describe "#ensure_metadata_consistency" do
    let(:organization) { create(:organization) }
    let(:invoice) { create(:invoice, organization:) }
    let(:customer) { invoice.customer }

    context "when metadata is consistent" do
      it "creates credit note with metadata in the same transaction" do
        credit_note = nil
        metadata = nil

        expect do
          described_class.transaction do
            credit_note = create(:credit_note, invoice:, customer:, organization:)
            metadata = create(:item_metadata, owner: credit_note, organization:, value: {"key" => "value"})
            credit_note.update!(metadata_id: metadata.id)
          end
        end.to change(described_class, :count).by(1).and change(Metadata::ItemMetadata, :count).by(1)

        expect(credit_note.reload.metadata).to eq(metadata)
        expect(metadata.reload.owner_id).to eq(credit_note.id)
      end

      it "is valid when metadata belongs to credit note and same organization" do
        credit_note = create(:credit_note, :with_metadata, invoice:, customer:, organization:)

        expect(credit_note).to be_valid
        expect(credit_note.metadata.owner_id).to eq(credit_note.id)
        expect(credit_note.metadata.organization_id).to eq(credit_note.organization_id)
      end
    end

    context "when metadata organization does not match credit note organization" do
      it "adds an error" do
        credit_note = create(:credit_note, invoice:, customer:, organization:)
        other_organization = create(:organization)

        # Create metadata with correct owner/organization, then manually change organization_id
        # to simulate inconsistent state for validation testing
        metadata = create(:item_metadata, owner: credit_note, organization:, value: {"key" => "value"})
        credit_note.metadata_id = metadata.id

        # Manually set the metadata's organization to a different one (in-memory only)
        # to test the validation logic
        allow(credit_note).to receive(:metadata).and_return(
          Metadata::ItemMetadata.new(
            id: metadata.id,
            owner: credit_note,
            organization: other_organization,
            value: {"key" => "value"}
          )
        )

        expect(credit_note).not_to be_valid
        expect(credit_note.errors[:metadata])
          .to include("must belong to the same organization as the credit note")
      end
    end
  end

  # rubocop:disable Rails/SkipsModelValidations
  describe "database constraints" do
    let(:organization) { create(:organization) }
    let(:invoice) { create(:invoice, organization:) }
    let(:customer) { invoice.customer }

    it "forbids reference to non-existent metadata" do
      credit_note = create(:credit_note, invoice:, customer:, organization:)
      invalid_uuid = SecureRandom.uuid

      expect do
        credit_note.update_columns(metadata_id: invalid_uuid)
        ActiveRecord::Base.connection.execute("SET CONSTRAINTS fk_credit_notes_metadata IMMEDIATE")
      end.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "forbids metadata belonging to different credit note" do
      credit_note = create(:credit_note, invoice:, customer:, organization:)
      other_credit_note = create(:credit_note, organization:)
      metadata = create(:item_metadata, owner: other_credit_note, organization:)

      expect do
        credit_note.update_columns(metadata_id: metadata.id)
        ActiveRecord::Base.connection.execute("SET CONSTRAINTS fk_credit_notes_metadata IMMEDIATE")
      end.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "forbids metadata from different organization" do
      credit_note = create(:credit_note, invoice:, customer:, organization:)
      other_organization = create(:organization)

      # Create metadata with mismatched organization, bypassing validation
      metadata = Metadata::ItemMetadata.new(
        owner: credit_note,
        organization: other_organization,
        value: {"key" => "value"}
      )
      metadata.save!(validate: false)

      expect do
        credit_note.update_columns(metadata_id: metadata.id)
        ActiveRecord::Base.connection.execute("SET CONSTRAINTS fk_credit_notes_metadata IMMEDIATE")
      end.to raise_error(ActiveRecord::StatementInvalid)
    end
  end
  # rubocop:enable Rails/SkipsModelValidations
end
