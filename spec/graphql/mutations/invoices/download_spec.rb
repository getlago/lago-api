# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Invoices::Download, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }

  let(:mutation) do
    <<~GQL
      mutation($input: DownloadInvoiceInput!) {
        downloadInvoice(input: $input) {
          id
        }
      }
    GQL
  end

  let(:pdf_generator) { instance_double(Utils::PdfGenerator) }

  let(:pdf_response) do
    BaseService::Result.new.tap { |r| r.io = StringIO.new(pdf_content) }
  end

  let(:pdf_content) do
    File.read(Rails.root.join("spec/fixtures/blank.pdf"))
  end

  before do
    allow(Utils::PdfGenerator).to receive(:new)
      .and_return(pdf_generator)
    allow(pdf_generator).to receive(:call)
      .and_return(pdf_response)
  end

  it "generates the PDF for the given invoice" do
    freeze_time do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: mutation,
        variables: {
          input: {id: invoice.id}
        }
      )

      result_data = result["data"]["downloadInvoice"]

      aggregate_failures do
        expect(result_data["id"]).to be_present
      end
    end
  end

  context "without current user" do
    it "returns an error" do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {id: invoice.id}
        }
      )

      expect_unauthorized_error(result)
    end
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {
          input: {id: invoice.id}
        }
      )

      expect_forbidden_error(result)
    end
  end
end
