# frozen_string_literal: true

module Invoices
  class GenerateService < BaseService
    include ActiveSupport::NumberHelper

    def generate_from_api(invoice)
      generate_pdf(invoice)

      SendWebhookJob.perform_later('invoice.generated', invoice)
    end

    def generate(invoice_id:)
      invoice = Invoice.find_by(id: invoice_id)

      return result.fail!(code: 'not_found') if invoice.blank?

      generate_pdf(invoice) if invoice.file.blank?

      result.invoice = invoice

      result
    end

    private

    def generate_pdf(invoice)
      template = File.read(Rails.root.join('app/views/templates/invoice.slim'), encoding: 'UTF-8')
      invoice_html = Slim::Template.new { template }.render(invoice)

      pdf_url = URI.join(ENV['LAGO_PDF_URL'], '/forms/chromium/convert/html').to_s
      http_client = LagoHttpClient::Client.new(pdf_url)
      response = http_client.post_multipart_file(
        invoice_html,
        'text/html',
        'index.html',
        scale: '1.28',
        marginTop: '0.42',
        marginBottom: '0.42',
        marginLeft: '0.42',
        marginRight: '0.42',
      )

      invoice.file.attach(
        io: StringIO.new(response.body.force_encoding('UTF-8')),
        filename: "#{invoice.number}.pdf",
        content_type: 'application/pdf',
      )

      invoice.save!
    end
  end
end
