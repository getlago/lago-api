# frozen_string_literal: true

RSpec.shared_examples "a payment request index endpoint" do
  let(:organization) { create(:organization) }
  let(:params) { {} }

  let(:customer) { create(:customer, organization:) }
  let(:payment_request) { create(:payment_request, customer:) }
  let(:second_payment_request) { create(:payment_request, customer:) }
  # Customers whose payment requests the endpoint lists in the N+1 context: a customer-scoped endpoint lists only `customer`
  let(:listed_customers) { [customer, other_customer] }

  include_examples "requires API permission", "payment_request", "read"

  context "without filters" do
    before do
      payment_request
      second_payment_request
    end

    it "returns organization's payment requests" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:payment_requests].count).to eq(2)
      expect(json[:payment_requests].map { |r| r[:lago_id] }).to contain_exactly(
        payment_request.id,
        second_payment_request.id
      )
    end
  end

  context "with currency filter" do
    let!(:usd_payment_request) { create(:payment_request, customer:, amount_currency: "USD") }
    let(:params) { {currency: "EUR"} }

    before do
      payment_request
      usd_payment_request
    end

    it "returns only payment requests with matching currency" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:payment_requests].count).to eq(1)
      expect(json[:payment_requests].first[:lago_id]).to eq(payment_request.id)
    end
  end

  context "with payment_status filter" do
    let(:second_payment_request) { create(:payment_request, :succeeded, customer:) }
    let(:params) { {payment_status: "pending"} }

    before do
      payment_request
      second_payment_request
    end

    it "returns payment requests with the given payment status" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:payment_requests].count).to eq(1)
      expect(json[:payment_requests].map { |r| r[:lago_id] }).to contain_exactly(
        payment_request.id
      )
    end
  end

  context "with N+1 query detection", bullet: {n_plus_one_query: true, unused_eager_loading: false} do
    let(:customer) { create(:customer, organization:, payment_provider: "stripe") }
    let(:other_customer) { create(:customer, organization:, payment_provider: "gocardless") }
    let(:other_billing_entity) { create(:billing_entity, organization:) }

    before do
      # NOTE: The list does not preload the invoice files yet: this context covers the customer and billing entity loads.
      # Unlike the unused eager loading safelist of credit_note_index.rb, this one hides n_plus_one_query,
      # so the after block removes it: Bullet keeps its safelist across examples.
      Bullet.add_safelist(type: :n_plus_one_query, class_name: "Invoice", association: :file_attachment)
      Bullet.add_safelist(type: :n_plus_one_query, class_name: "Invoice", association: :xml_file_attachment)

      create(:stripe_customer, customer:)
      create(:gocardless_customer, customer: other_customer)

      [customer, other_customer].each do |payment_request_customer|
        create(:customer_metadata, customer: payment_request_customer, key: "lead_name", value: payment_request_customer.external_id)
        create(:customer_metadata, customer: payment_request_customer, key: "region", value: "eu")

        2.times do
          invoices = [payment_request_customer.billing_entity, other_billing_entity].map do |billing_entity|
            create(:invoice, organization:, customer: payment_request_customer, billing_entity:)
          end
          create(:payment_request, customer: payment_request_customer, invoices:)
        end
      end
    end

    after do
      Bullet.delete_safelist(type: :n_plus_one_query, class_name: "Invoice", association: :file_attachment)
      Bullet.delete_safelist(type: :n_plus_one_query, class_name: "Invoice", association: :xml_file_attachment)
    end

    it "loads the customer associations and the invoice billing entities once per page" do
      metadata_queries = capture_sql { subject }.grep(/FROM "customer_metadata"/)

      expect(response).to have_http_status(:success)
      expect(json[:payment_requests].count).to eq(2 * listed_customers.count)
      expect(json[:payment_requests].map { it[:customer][:lago_id] }.uniq).to match_array(listed_customers.map(&:id))
      expect(metadata_queries.count).to eq(1)

      json[:payment_requests].each do |payment_request|
        rendered_customer = payment_request[:customer]
        expected_customer = listed_customers.find { it.id == rendered_customer[:lago_id] }

        expect(rendered_customer[:metadata].map { it.slice(:key, :value) }).to match_array(
          [{key: "lead_name", value: expected_customer.external_id}, {key: "region", value: "eu"}]
        )
        expect(rendered_customer[:billing_entity_code]).to eq(expected_customer.billing_entity.code)
        expect(rendered_customer[:billing_configuration][:provider_customer_id]).to eq(
          (expected_customer.stripe_customer || expected_customer.gocardless_customer).provider_customer_id
        )
        expect(payment_request[:invoices].pluck(:billing_entity_code)).to match_array(
          [expected_customer.billing_entity.code, other_billing_entity.code]
        )
      end
    end
  end
end
