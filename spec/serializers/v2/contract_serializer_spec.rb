# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::ContractSerializer do
  subject(:payload) { described_class.new(contract, root_name: "contract", includes:).serialize }

  let(:includes) { %i[applied_rate_cards] }

  let(:contract) { create(:contract) }
  let(:created_at) { Time.zone.parse("2026-09-28T10:00:00.000001Z") }
  # Oldest first, the reverse of the listed order.
  let!(:applied_rate_cards) { [2, 1, 0, 0].map { create(:contract_rate_card, organization: contract.organization, contract:, created_at: created_at - it.seconds) } }

  it "embeds the applied rate cards newest first, ties ordered by id" do
    expected = applied_rate_cards.sort_by { [it.created_at, it.id] }.reverse.map(&:id)

    expect(payload[:applied_rate_cards].pluck(:lago_id)).to eq(expected)
  end

  context "with invoice custom sections" do
    let(:includes) { %i[applied_invoice_custom_sections] }
    # Oldest first, the reverse of the listed order, on sections created the other way around: listed
    # by the sections instead of the links, the oldest link would come first.
    let!(:applied_sections) do
      [1, 0, 0].map do |age|
        invoice_custom_section = create(:invoice_custom_section, organization: contract.organization, created_at: created_at + age.seconds)
        create(:contract_applied_invoice_custom_section, contract:, invoice_custom_section:, created_at: created_at - age.seconds)
      end
    end

    it "embeds them newest first, ties ordered by id" do
      expected = applied_sections.sort_by { [it.created_at, it.id] }.reverse.map(&:id)

      expect(payload[:applied_invoice_custom_sections].pluck(:lago_id)).to eq(expected)
    end
  end
end
