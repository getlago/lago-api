# frozen_string_literal: true

require "rails_helper"

describe InvoicesPreloader do
  subject(:preloader) { described_class.new([invoice], *scopes) }

  let(:invoice) { create(:invoice) }

  before do
    create(:credit_note, invoice:, offset_amount_cents: 5_00, refund_amount_cents: 5_00)
    create(:credit_note, invoice:, offset_amount_cents: 10_00, refund_amount_cents: 10_00, credit_status: :voided)
    create(:credit_note, invoice:, offset_amount_cents: 20_00, refund_amount_cents: 20_00, status: :draft)

    credit_note = create(:credit_note, invoice:)
    fee1 = create(:fee, invoice:)
    fee2 = create(:fee, invoice:)

    create(:credit_note_item, credit_note:, fee: fee1, amount_cents: 5_00)
    create(:credit_note_item, credit_note:, fee: fee2, amount_cents: 10_00)
    create(:credit_note_item, credit_note:, fee: fee2, amount_cents: 15_00)
  end

  describe "#call" do
    context "when no :scopes are passed" do
      let(:scopes) { [] }

      it "scopes and caches all amounts" do
        preloader.call

        expect(invoice.preloader_cache).to eq(
          offset_amount_cents: 15_00,
          refunded_amount_cents: 35_00,
          has_non_voided_credit_notes: true
        )

        expect(invoice.fees.first.preloader_cache).to eq(
          credited_amount_cents: 5_00
        )

        expect(invoice.fees.last.preloader_cache).to eq(
          credited_amount_cents: 25_00
        )
      end
    end

    context "when specific :scopes are passed" do
      let(:scopes) { [:offset_amount_cents] }

      it "scopes and caches only the passed :scopes" do
        preloader.call

        expect(invoice.preloader_cache).to eq(
          offset_amount_cents: 15_00
        )

        expect(invoice.fees.first.preloader_cache).to eq({})
        expect(invoice.fees.last.preloader_cache).to eq({})
      end
    end
  end
end
