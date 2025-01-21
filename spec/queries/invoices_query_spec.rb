# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InvoicesQuery, type: :query do
  subject(:result) do
    described_class.call(organization:, pagination:, search_term:, filters:)
  end

  let(:returned_ids) { result.invoices.pluck(:id) }
  let(:pagination) { nil }
  let(:search_term) { nil }
  let(:filters) { nil }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer_first) { create(:customer, organization:, name: 'Rick Sanchez', firstname: 'RickFirst', lastname: 'SanchezLast', email: 'pickle@hotmail.com') }
  let(:customer_second) { create(:customer, organization:, name: 'Morty Smith', firstname: 'MortyFirst', lastname: 'SmithLast', email: 'ilovejessica@gmail.com') }
  let(:invoice_first) do
    create(
      :invoice,
      organization:,
      status: 'finalized',
      payment_status: 'succeeded',
      customer: customer_first,
      number: '1111111111',
      issuing_date: 1.week.ago
    )
  end
  let(:invoice_second) do
    create(
      :invoice,
      organization:,
      status: 'finalized',
      payment_status: 'pending',
      customer: customer_second,
      number: '2222222222',
      issuing_date: 2.weeks.ago
    )
  end
  let(:invoice_third) do
    create(
      :invoice,
      organization:,
      status: 'finalized',
      payment_status: 'failed',
      payment_overdue: true,
      customer: customer_first,
      number: '3333333333',
      issuing_date: 3.weeks.ago
    )
  end
  let(:invoice_fourth) do
    create(
      :invoice,
      organization:,
      status: 'draft',
      payment_status: 'pending',
      customer: customer_second,
      number: '4444444444',
      currency: 'USD'
    )
  end
  let(:invoice_fifth) do
    create(
      :invoice,
      :credit,
      organization:,
      status: 'draft',
      payment_status: 'pending',
      customer: customer_first,
      number: '5555555555'
    )
  end
  let(:invoice_sixth) do
    create(
      :invoice,
      :dispute_lost,
      organization:,
      payment_status: 'pending',
      customer: customer_first,
      number: '6666666666'
    )
  end

  before do
    invoice_first
    invoice_second
    invoice_third
    invoice_fourth
    invoice_fifth
    invoice_sixth
  end

  it 'returns all invoices' do
    expect(result).to be_success
    expect(returned_ids.count).to eq(6)
    expect(returned_ids).to include(invoice_first.id)
    expect(returned_ids).to include(invoice_second.id)
    expect(returned_ids).to include(invoice_third.id)
    expect(returned_ids).to include(invoice_fourth.id)
    expect(returned_ids).to include(invoice_fifth.id)
    expect(returned_ids).to include(invoice_sixth.id)
  end

  context "when invoices have the same values for the ordering criteria" do
    let(:invoice_second) do
      create(
        :invoice,
        organization:,
        id: "00000000-0000-0000-0000-000000000000",
        status: 'finalized',
        payment_status: 'pending',
        customer: customer_second,
        number: '2222222222',
        issuing_date: invoice_first.issuing_date,
        created_at: invoice_first.created_at
      )
    end

    it "returns a consistent list" do
      expect(result).to be_success
      expect(returned_ids.count).to eq(6)
      expect(returned_ids).to include(invoice_first.id)
      expect(returned_ids).to include(invoice_second.id)
      expect(returned_ids.index(invoice_first.id)).to be > returned_ids.index(invoice_second.id)
    end
  end

  context 'with pagination' do
    let(:pagination) { {page: 2, limit: 3} }

    it 'applies the pagination' do
      aggregate_failures do
        expect(result).to be_success
        expect(result.invoices.count).to eq(3)
        expect(result.invoices.current_page).to eq(2)
        expect(result.invoices.prev_page).to eq(1)
        expect(result.invoices.next_page).to be_nil
        expect(result.invoices.total_pages).to eq(2)
        expect(result.invoices.total_count).to eq(6)
      end
    end
  end

  context 'when filtering by draft status' do
    let(:filters) { {status: 'draft'} }

    it 'returns 2 invoices' do
      aggregate_failures do
        expect(returned_ids.count).to eq(2)
        expect(returned_ids).not_to include(invoice_first.id)
        expect(returned_ids).not_to include(invoice_second.id)
        expect(returned_ids).not_to include(invoice_third.id)
        expect(returned_ids).to include(invoice_fourth.id)
        expect(returned_ids).to include(invoice_fifth.id)
      end
    end
  end

  context 'when filtering by failed payment_status' do
    let(:filters) { {payment_status: 'failed'} }

    it 'returns 1 invoices' do
      aggregate_failures do
        expect(returned_ids.count).to eq(1)
        expect(returned_ids).not_to include(invoice_first.id)
        expect(returned_ids).not_to include(invoice_second.id)
        expect(returned_ids).to include(invoice_third.id)
        expect(returned_ids).not_to include(invoice_fourth.id)
        expect(returned_ids).not_to include(invoice_fifth.id)
      end
    end
  end

  context 'when filtering by succeeded and failed payment_status' do
    let(:filters) { {payment_status: ['succeeded', 'failed']} }

    it 'returns 1 invoices' do
      aggregate_failures do
        expect(returned_ids.count).to eq(2)
        expect(returned_ids).to include(invoice_first.id)
        expect(returned_ids).not_to include(invoice_second.id)
        expect(returned_ids).to include(invoice_third.id)
        expect(returned_ids).not_to include(invoice_fourth.id)
        expect(returned_ids).not_to include(invoice_fifth.id)
      end
    end
  end

  context 'when filtering by payment dispute lost' do
    let(:filters) { {payment_dispute_lost: true} }

    it 'returns 1 invoices' do
      aggregate_failures do
        expect(returned_ids.count).to eq(1)
        expect(returned_ids).not_to include(invoice_first.id)
        expect(returned_ids).not_to include(invoice_second.id)
        expect(returned_ids).not_to include(invoice_third.id)
        expect(returned_ids).not_to include(invoice_fourth.id)
        expect(returned_ids).not_to include(invoice_fifth.id)
        expect(returned_ids).to include(invoice_sixth.id)
      end
    end
  end

  context 'when filtering by payment dispute lost false' do
    let(:filters) { {payment_dispute_lost: false} }

    it 'returns 1 invoices' do
      aggregate_failures do
        expect(returned_ids.count).to eq(5)
        expect(returned_ids).to include(invoice_first.id)
        expect(returned_ids).to include(invoice_second.id)
        expect(returned_ids).to include(invoice_third.id)
        expect(returned_ids).to include(invoice_fourth.id)
        expect(returned_ids).to include(invoice_fifth.id)
        expect(returned_ids).not_to include(invoice_sixth.id)
      end
    end
  end

  context 'when filtering by payment overdue' do
    let(:filters) { {payment_overdue: true} }

    it 'returns expected invoices' do
      expect(result.invoices.pluck(:id)).to eq([invoice_third.id])
    end
  end

  context 'when filtering by payment overdue false' do
    let(:filters) { {payment_overdue: false} }

    it 'returns expected invoices' do
      aggregate_failures do
        expect(returned_ids.count).to eq(5)
        expect(returned_ids).to include(invoice_first.id)
        expect(returned_ids).to include(invoice_second.id)
        expect(returned_ids).not_to include(invoice_third.id)
        expect(returned_ids).to include(invoice_fourth.id)
        expect(returned_ids).to include(invoice_fifth.id)
        expect(returned_ids).to include(invoice_sixth.id)
      end
    end
  end

  context 'when filtering by partially_paid' do
    let(:invoice_first) do
      create(
        :invoice,
        organization:,
        status: 'finalized',
        payment_status: 'succeeded',
        customer: customer_first,
        number: '1111111111',
        issuing_date: 1.week.ago,
        total_amount_cents: 2000,
        total_paid_amount_cents: 2000
      )
    end
    let(:invoice_second) do
      create(
        :invoice,
        organization:,
        status: 'finalized',
        payment_status: 'pending',
        customer: customer_second,
        number: '2222222222',
        issuing_date: 2.weeks.ago,
        total_amount_cents: 2000,
        total_paid_amount_cents: 1500
      )
    end

    context 'when partially_paid is true' do
      let(:filters) { {partially_paid: true} }

      it 'returns only partially paid invoices' do
        aggregate_failures do
          expect(returned_ids.count).to eq(1)
          expect(returned_ids).to include(invoice_second.id)
          expect(returned_ids).not_to include(invoice_first.id)
        end
      end
    end

    context 'when partially_paid is false' do
      let(:filters) { {partially_paid: false} }

      it 'returns only fully paid and unpaid invoices' do
        aggregate_failures do
          expect(returned_ids.count).to eq(5)
          expect(returned_ids).not_to include(invoice_second.id)
          expect(returned_ids).to include(invoice_first.id)
        end
      end
    end

    context 'when partially_paid is nil' do
      let(:filters) { {partially_paid: nil} }

      it 'returns all invoices' do
        aggregate_failures do
          expect(returned_ids.count).to eq(6)
        end
      end
    end
  end

  context 'when filtering by credit invoice_type' do
    let(:filters) { {invoice_type: 'credit'} }

    it 'returns 1 invoice' do
      aggregate_failures do
        expect(returned_ids).to eq [invoice_fifth.id]
      end
    end
  end

  context 'when filtering by USD currency' do
    let(:filters) { {currency: 'USD'} }

    it 'returns 1 invoice' do
      aggregate_failures do
        expect(returned_ids).to eq [invoice_fourth.id]
      end
    end
  end

  context 'when filtering by customer_external_id' do
    let(:filters) { {customer_external_id: customer_second.external_id} }

    it 'returns 2 invoices' do
      aggregate_failures do
        expect(returned_ids).not_to include(invoice_first.id)
        expect(returned_ids).to include(invoice_second.id)
        expect(returned_ids).not_to include(invoice_third.id)
        expect(returned_ids).to include(invoice_fourth.id)
        expect(returned_ids).not_to include(invoice_fifth.id)
        expect(returned_ids).not_to include(invoice_sixth.id)
      end
    end

    context "with searching for /2222/ term" do
      let(:search_term) { "2222" }

      it "returns 1 invoices" do
        aggregate_failures do
          expect(result.invoices.count).to eq(1)
          expect(returned_ids).not_to include(invoice_first.id)
          expect(returned_ids).to include(invoice_second.id)
          expect(returned_ids).not_to include(invoice_third.id)
          expect(returned_ids).not_to include(invoice_fourth.id)
          expect(returned_ids).not_to include(invoice_fifth.id)
        end
      end
    end
  end

  context 'when filtering by issuing_date_from' do
    let(:filters) { {issuing_date_from: 2.days.ago.iso8601.to_date.to_s} }

    it 'returns 4 invoices' do
      aggregate_failures do
        expect(returned_ids).not_to include(invoice_first.id)
        expect(returned_ids).not_to include(invoice_second.id)
        expect(returned_ids).not_to include(invoice_third.id)
        expect(returned_ids).to include(invoice_fourth.id)
        expect(returned_ids).to include(invoice_fifth.id)
        expect(returned_ids).to include(invoice_sixth.id)
      end
    end

    context 'with invalid date' do
      let(:filters) { {issuing_date_from: 'invalid_date_value'} }

      it 'returns a failed result' do
        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:issuing_date_from]).to include('invalid_date')
        end
      end
    end
  end

  context 'when filtering by issuing_date_to' do
    let(:filters) { {issuing_date_to: 2.weeks.ago.iso8601.to_date.to_s} }

    it 'returns 2 invoices' do
      aggregate_failures do
        expect(returned_ids).not_to include(invoice_first.id)
        expect(returned_ids).to include(invoice_second.id)
        expect(returned_ids).to include(invoice_third.id)
        expect(returned_ids).not_to include(invoice_fourth.id)
        expect(returned_ids).not_to include(invoice_fifth.id)
        expect(returned_ids).not_to include(invoice_sixth.id)
      end
    end

    context 'with invalid date' do
      let(:filters) { {issuing_date_to: 'invalid_date_value'} }

      it 'returns a failed result' do
        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:issuing_date_to]).to include('invalid_date')
        end
      end
    end
  end

  context 'when filtering by issuing_date from and to' do
    let(:filters) do
      {
        issuing_date_from: 2.weeks.ago.iso8601,
        issuing_date_to: 1.week.ago.iso8601
      }
    end

    it 'returns 2 invoices' do
      aggregate_failures do
        expect(returned_ids).to include(invoice_first.id)
        expect(returned_ids).to include(invoice_second.id)
        expect(returned_ids).not_to include(invoice_third.id)
        expect(returned_ids).not_to include(invoice_fourth.id)
        expect(returned_ids).not_to include(invoice_fifth.id)
        expect(returned_ids).not_to include(invoice_sixth.id)
      end
    end
  end

  context 'when searching for a part of an invoice id' do
    let(:search_term) { invoice_fourth.id.scan(/.{10}/).first }

    it 'returns 1 invoices' do
      aggregate_failures do
        expect(returned_ids.count).to eq(1)
        expect(returned_ids).not_to include(invoice_first.id)
        expect(returned_ids).not_to include(invoice_second.id)
        expect(returned_ids).not_to include(invoice_third.id)
        expect(returned_ids).to include(invoice_fourth.id)
        expect(returned_ids).not_to include(invoice_fifth.id)
      end
    end
  end

  context 'when searching an invoice number' do
    let(:search_term) { invoice_first.number }

    it 'returns 1 invoices' do
      aggregate_failures do
        expect(returned_ids.count).to eq(1)
        expect(returned_ids).to include(invoice_first.id)
        expect(returned_ids).not_to include(invoice_second.id)
        expect(returned_ids).not_to include(invoice_third.id)
        expect(returned_ids).not_to include(invoice_fourth.id)
        expect(returned_ids).not_to include(invoice_fifth.id)
      end
    end
  end

  context 'when searching a customer external id' do
    let(:search_term) { customer_second.external_id }

    it 'returns 2 invoices' do
      aggregate_failures do
        expect(returned_ids.count).to eq(2)
        expect(returned_ids).not_to include(invoice_first.id)
        expect(returned_ids).to include(invoice_second.id)
        expect(returned_ids).not_to include(invoice_third.id)
        expect(returned_ids).to include(invoice_fourth.id)
        expect(returned_ids).not_to include(invoice_fifth.id)
      end
    end
  end

  context 'when searching for /rick/ term' do
    let(:search_term) { 'rick' }

    it 'returns 3 invoices' do
      aggregate_failures do
        expect(returned_ids.count).to eq(4)
        expect(returned_ids).to include(invoice_first.id)
        expect(returned_ids).not_to include(invoice_second.id)
        expect(returned_ids).to include(invoice_third.id)
        expect(returned_ids).not_to include(invoice_fourth.id)
        expect(returned_ids).to include(invoice_fifth.id)
        expect(returned_ids).to include(invoice_sixth.id)
      end
    end
  end

  context 'when searching for /gmail/ term' do
    let(:search_term) { 'gmail' }

    it 'returns 2 invoices' do
      aggregate_failures do
        expect(returned_ids.count).to eq(2)
        expect(returned_ids).not_to include(invoice_first.id)
        expect(returned_ids).to include(invoice_second.id)
        expect(returned_ids).not_to include(invoice_third.id)
        expect(returned_ids).to include(invoice_fourth.id)
        expect(returned_ids).not_to include(invoice_fifth.id)
      end
    end
  end

  context 'when searching for /44444444/ term' do
    let(:search_term) { '44444444' }
    let(:filters) { {customer_id: customer_second.id} }

    it 'returns 1 invoices' do
      aggregate_failures do
        expect(returned_ids.count).to eq(1)
        expect(returned_ids).not_to include(invoice_first.id)
        expect(returned_ids).not_to include(invoice_second.id)
        expect(returned_ids).not_to include(invoice_third.id)
        expect(returned_ids).to include(invoice_fourth.id)
        expect(returned_ids).not_to include(invoice_fifth.id)
      end
    end
  end

  context 'when searching for another customer with no invoice' do
    let(:filters) { {customer_id: create(:customer, organization:).id} }

    it 'returns 0 invoices' do
      aggregate_failures do
        expect(returned_ids.count).to eq(0)
        expect(returned_ids).not_to include(invoice_first.id)
        expect(returned_ids).not_to include(invoice_second.id)
        expect(returned_ids).not_to include(invoice_third.id)
        expect(returned_ids).not_to include(invoice_fourth.id)
      end
    end
  end

  context 'when searching for lastname "SanchezLast"' do
    let(:search_term) { 'SanchezLast' }

    it 'returns the correct invoices for this customer' do
      aggregate_failures do
        expect(returned_ids.count).to eq(4)
        expect(returned_ids).to include(invoice_first.id)
        expect(returned_ids).not_to include(invoice_second.id)
        expect(returned_ids).to include(invoice_third.id)
        expect(returned_ids).not_to include(invoice_fourth.id)
        expect(returned_ids).to include(invoice_fifth.id)
        expect(returned_ids).to include(invoice_sixth.id)
      end
    end
  end

  context 'when searching for firstname "MortyFirst"' do
    let(:search_term) { 'MortyFirst' }

    it 'returns the correct invoices for this customer' do
      aggregate_failures do
        expect(returned_ids.count).to eq(2)
        expect(returned_ids).not_to include(invoice_first.id)
        expect(returned_ids).to include(invoice_second.id)
        expect(returned_ids).not_to include(invoice_third.id)
        expect(returned_ids).to include(invoice_fourth.id)
        expect(returned_ids).not_to include(invoice_fifth.id)
        expect(returned_ids).not_to include(invoice_sixth.id)
      end
    end
  end

  context "when amount filters applied" do
    let(:filters) { {amount_from:, amount_to:} }

    let!(:invoices) do
      (1..5).to_a.map do |i|
        create(:invoice, total_amount_cents: i.succ * 1_000, organization:)
      end # from smallest to biggest
    end

    context "when only amount from provided" do
      let(:amount_from) { invoices.second.total_amount_cents }
      let(:amount_to) { nil }

      it "returns invoices with total cents amount bigger or equal to provided value" do
        expect(result).to be_success
        expect(result.invoices.pluck(:id)).to match_array invoices[1..].pluck(:id)
      end
    end

    context "when only amount to provided" do
      let(:amount_from) { 100 }
      let(:amount_to) { invoices.fourth.total_amount_cents }

      it "returns invoices with total cents amount lower or equal to provided value" do
        expect(result).to be_success
        expect(result.invoices.pluck(:id)).to match_array invoices[..3].pluck(:id)
      end
    end

    context "when both amount from and amount to provided" do
      let(:amount_from) { invoices.second.total_amount_cents }
      let(:amount_to) { invoices.fourth.total_amount_cents }

      it "returns invoices with total cents amount in provided range" do
        expect(result).to be_success
        expect(result.invoices.pluck(:id)).to match_array invoices[1..3].pluck(:id)
      end
    end
  end

  context "when metadata filters applied" do
    let(:filters) { {metadata:} }

    context "when single filter provided" do
      context "when value is present" do
        let(:metadata) { {red: 5} }
        let(:matching_invoice) { create(:invoice, organization:) }

        before do
          create(:invoice_metadata, invoice: matching_invoice, key: :red, value: 5)

          create(:invoice, organization:) do |invoice|
            create(:invoice_metadata, invoice:)
          end
        end

        it "returns invoices with matching metadata filters" do
          expect(result).to be_success
          expect(result.invoices.pluck(:id)).to contain_exactly matching_invoice.id
        end
      end

      context "when value is absent" do
        let(:metadata) { {red: ""} }

        let!(:matching_invoices) do
          [
            create(:invoice, organization:),
            create(:invoice, organization:) do |invoice|
              create(:invoice_metadata, invoice:, key: :orange, value: 3)
            end
          ]
        end

        before do
          create(:invoice, organization:) do |invoice|
            create(:invoice_metadata, invoice:, key: :red, value: 5)
          end

          [invoice_first, invoice_second, invoice_third, invoice_fourth, invoice_fifth, invoice_sixth].each do |invoice|
            create(:invoice_metadata, invoice:, key: :red, value: 5)
          end
        end

        it "returns invoices without provided key metadata or without metadata at all" do
          expect(result).to be_success
          expect(result.invoices.pluck(:id)).to match_array matching_invoices.pluck(:id)
        end
      end
    end

    context "when multiple filters provided" do
      let(:metadata) do
        {
          red: 5,
          orange: 3,
          green: ""
        }
      end

      let!(:matching_invoices) { create_pair(:invoice, organization:) }

      before do
        matching_invoices.each do |invoice|
          create(:invoice_metadata, invoice:, key: :red, value: 5)
          create(:invoice_metadata, invoice:, key: :orange, value: 3)
        end

        create(:invoice, organization:) do |invoice|
          create(:invoice_metadata, invoice:, key: :red, value: 5)
          create(:invoice_metadata, invoice:, key: :pink, value: 7)
        end

        create(:invoice, organization:)

        create(:invoice, organization:) do |invoice|
          create(:invoice_metadata, invoice:, key: :red, value: 5)
          create(:invoice_metadata, invoice:, key: :orange, value: 3)
          create(:invoice_metadata, invoice:, key: :green, value: 1)
        end
      end

      it "returns invoices with matching metadata filters" do
        expect(result).to be_success
        expect(result.invoices.pluck(:id)).to match_array matching_invoices.pluck(:id)
      end
    end
  end

  context "with multiple filters applied at the same time" do
    let(:search_term) { invoice.number.first(5) }

    let(:filters) do
      {
        currency: invoice.currency,
        customer_external_id: invoice.customer.external_id,
        customer_id: invoice.customer.id,
        invoice_type: invoice.invoice_type,
        issuing_date_from: invoice.issuing_date,
        issuing_date_to: invoice.issuing_date,
        status: invoice.status,
        payment_status: invoice.payment_status,
        payment_dispute_lost: invoice.payment_dispute_lost_at.present?,
        payment_overdue: invoice.payment_overdue,
        amount_from: invoice.total_amount_cents,
        amount_to: invoice.total_amount_cents,
        metadata: invoice.metadata.to_h { |item| [item.key, item.value] }
      }
    end

    let!(:invoice) { create(:invoice, currency: "EUR", organization:) }

    before { create(:invoice, currency: "USD", organization:) }

    it "returns invoices matching all provided filters" do
      expect(result).to be_success
      expect(result.invoices.pluck(:id)).to contain_exactly invoice.id
    end
  end
end
