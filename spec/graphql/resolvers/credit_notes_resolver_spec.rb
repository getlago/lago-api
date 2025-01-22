# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::CreditNotesResolver, type: :graphql do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:
    )
  end

  let(:required_permission) { 'credit_notes:view' }
  let(:query) do
    <<~GQL
      query {
        creditNotes(#{[arguments, "limit: 5"].join(", ")}) {
          collection { id number }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:arguments) { "" }

  let(:response_collection) { result['data']['creditNotes']['collection'] }

  before { create(:credit_note, :draft, customer:) }

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'credit_notes:view'

  context 'with no arguments' do
    let!(:credit_note) { create(:credit_note, customer:) }

    it 'returns finalized credit_notes' do
      expect(response_collection.pluck('id')).to contain_exactly credit_note.id

      expect(result['data']['creditNotes']['metadata']['currentPage']).to eq(1)
      expect(result['data']['creditNotes']['metadata']['totalCount']).to eq(1)
    end
  end

  context 'with currency' do
    let(:arguments) { "currency: #{credit_note.currency.upcase}" }
    let!(:credit_note) { create(:credit_note, customer:, total_amount_currency: "USD") }

    before { create(:credit_note, customer:, total_amount_currency: "EUR") }

    it 'returns finalized credit_notes matching currency' do
      expect(response_collection.pluck('id')).to contain_exactly credit_note.id
    end
  end

  context 'with customer_external_id' do
    let(:arguments) { "customerExternalId: #{customer.external_id.inspect}" }
    let!(:credit_note) { create(:credit_note, customer:) }

    before do
      another_customer = create(:customer, organization:)
      create(:credit_note, customer: another_customer)
    end

    it 'returns finalized credit_notes with matching customer external id' do
      expect(response_collection.pluck('id')).to contain_exactly credit_note.id
    end
  end

  context 'with customer_id' do
    let(:arguments) { "customerId: #{customer.id.inspect}" }
    let!(:credit_note) { create(:credit_note, customer:) }

    before do
      another_customer = create(:customer, organization:)
      create(:credit_note, customer: another_customer)
    end

    it 'returns finalized credit_notes with matching customer id' do
      expect(response_collection.pluck('id')).to contain_exactly credit_note.id
    end
  end

  context 'with reason' do
    let(:arguments) { "reason: [#{matching_reasons.map(&:to_s).join(", ")}]" }
    let(:matching_reasons) { CreditNote::REASON.sample(2) }

    let!(:credit_notes) do
      matching_reasons.map { |reason| create(:credit_note, reason:, customer:) }
    end

    before do
      create(
        :credit_note,
        reason: CreditNote::REASON.excluding(matching_reasons).sample,
        customer:
      )
    end

    it 'returns finalized credit_notes with matching reasons' do
      expect(response_collection.pluck('id')).to match_array credit_notes.pluck(:id)
    end
  end

  context 'with credit_status' do
    let(:arguments) { "creditStatus: [#{matching_credit_statuses.map(&:to_s).join(", ")}]" }
    let(:matching_credit_statuses) { CreditNote::CREDIT_STATUS.sample(2) }

    let!(:credit_notes) do
      matching_credit_statuses.map do |credit_status|
        create(:credit_note, credit_status:, customer:)
      end
    end

    before do
      create(
        :credit_note,
        credit_status: CreditNote::CREDIT_STATUS.excluding(matching_credit_statuses).sample,
        customer:
      )
    end

    it 'returns finalized credit_notes with matching credit statuses' do
      expect(response_collection.pluck('id')).to match_array credit_notes.pluck(:id)
    end
  end

  context 'with refund_status' do
    let(:arguments) { "refundStatus: [#{matching_refund_statuses.map(&:to_s).join(", ")}]" }
    let(:matching_refund_statuses) { CreditNote::REFUND_STATUS.sample(2) }

    let!(:credit_notes) do
      matching_refund_statuses.map do |refund_status|
        create(:credit_note, refund_status:, customer:)
      end
    end

    before do
      create(
        :credit_note,
        refund_status: CreditNote::REFUND_STATUS.excluding(matching_refund_statuses).sample,
        customer:
      )
    end

    it 'returns finalized credit_notes with matching refund statuses' do
      expect(response_collection.pluck('id')).to match_array credit_notes.pluck(:id)
    end
  end

  context 'with invoice_number' do
    let(:arguments) { "invoiceNumber: #{credit_note.invoice.number.inspect}" }
    let!(:credit_note) { create(:credit_note, customer:) }

    before { create(:credit_note, customer:) }

    it 'returns finalized credit_notes matching invoice number' do
      expect(response_collection.pluck('id')).to contain_exactly credit_note.id
    end
  end

  context 'with both issuing_date_from and issuing_date_to' do
    let(:arguments) do
      [
        "issuingDateFrom: #{credit_notes.second.issuing_date.to_s.inspect}",
        "issuingDateTo: #{credit_notes.fourth.issuing_date.to_s.inspect}"
      ].join(", ")
    end

    let!(:credit_notes) do
      (1..5).to_a.map do |i|
        create(:credit_note, issuing_date: i.days.ago, customer:)
      end.reverse # from oldest to newest
    end

    it 'returns finalized credit notes that were issued between provided dates' do
      expect(response_collection.pluck('id')).to match_array credit_notes[1..3].pluck(:id)
    end
  end

  context 'with both amount_from and amount_to' do
    let(:arguments) do
      [
        "amountFrom: #{credit_notes.second.total_amount_cents.inspect}",
        "amountTo: #{credit_notes.fourth.total_amount_cents.inspect}"
      ].join(", ")
    end

    let!(:credit_notes) do
      (1..5).to_a.map do |i|
        create(:credit_note, total_amount_cents: i.succ * 1_000, customer:)
      end # from smallest to biggest
    end

    it 'returns finalized credit notes total cents amount in provided range' do
      expect(response_collection.pluck('id')).to match_array credit_notes[1..3].pluck(:id)
    end
  end

  context 'with search_term' do
    let(:arguments) { "searchTerm: #{credit_note.number.inspect}" }
    let!(:credit_note) { create(:credit_note, customer:) }

    before { create(:credit_note, customer:) }

    it 'returns finalized credit_notes matching the terms' do
      expect(response_collection.pluck('id')).to contain_exactly credit_note.id
    end
  end

  context "when filtering by self billed invoice" do
    let(:self_billed_credit_note) do
      invoice = create(:invoice, :self_billed, customer:, organization:)

      create(:credit_note, invoice:, customer:)
    end

    let(:non_self_billed_credit_note) do
      create(:credit_note, customer:)
    end

    let(:query) do
      <<~GQL
        query {
          creditNotes(limit: 5, selfBilled: true) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    before do
      self_billed_credit_note
      non_self_billed_credit_note
    end

    it "returns all credit notes from self billed invoices" do
      expect(response_collection.count).to eq(1)
      expect(response_collection.first["id"]).to eq(self_billed_credit_note.id)

      expect(result["data"]["creditNotes"]["metadata"]["currentPage"]).to eq(1)
      expect(result["data"]["creditNotes"]["metadata"]["totalCount"]).to eq(1)
    end
  end
end
