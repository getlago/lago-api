# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequestMailer, type: :mailer do
  subject(:payment_request_mailer) { described_class }

  let(:organization) { create(:organization, document_number_prefix: 'ORG-123B') }
  let(:first_invoice) { create(:invoice, total_amount_cents: 1000, organization:) }
  let(:second_invoice) { create(:invoice, total_amount_cents: 2000, organization:) }
  let(:payment_request) { create(:payment_request, invoices: [first_invoice, second_invoice]) }

  before do
    first_invoice.file.attach(
      io: StringIO.new(File.read(Rails.root.join("spec/fixtures/blank.pdf"))),
      filename: "invoice.pdf",
      content_type: "application/pdf"
    )
    second_invoice.file.attach(
      io: StringIO.new(File.read(Rails.root.join("spec/fixtures/blank.pdf"))),
      filename: "invoice.pdf",
      content_type: "application/pdf"
    )
  end

  describe "#requested" do
    let(:payment_url) { Faker::Internet.url }
    let(:payment_url_result) do
      BaseService::Result.new.tap do |result|
        result.payment_url = payment_url
      end
    end

    before do
      allow(::PaymentRequests::Payments::GeneratePaymentUrlService)
        .to receive(:call)
        .and_return(payment_url_result)
    end

    specify do
      mailer = payment_request_mailer.with(payment_request:).requested

      expect(mailer.to).to eq([payment_request.email])
      expect(mailer.reply_to).to eq([payment_request.organization.email])
      expect(mailer.body.encoded).to include(first_invoice.number)
      expect(mailer.body.encoded).to include(second_invoice.number)
    end

    it "calls the generate payment url service" do
      mailer = payment_request_mailer.with(payment_request:).requested
      parsed_body = Nokogiri::HTML(mailer.body.encoded)

      expect(parsed_body.at_css("a#payment_link")["href"]).to eq(payment_url)
      expect(mailer.body.encoded).to include("Pay balance")
      expect(PaymentRequests::Payments::GeneratePaymentUrlService)
        .to have_received(:call)
        .with(payable: payment_request)
    end

    context "when no payment url is available" do
      let(:payment_url_result) do
        BaseService::Result.new.tap do |result|
          result.single_validation_failure!(error_code: "invalid_payment_provider")
        end
      end

      it "does not include the payment link" do
        mailer = payment_request_mailer.with(payment_request:).requested
        parsed_body = Nokogiri::HTML(mailer.body.encoded)

        expect(parsed_body.css("a#payment_link")).not_to be_present
        expect(mailer.body.encoded).not_to include("Pay balance")
      end
    end
  end
end
