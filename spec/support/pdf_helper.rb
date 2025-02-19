# frozen_string_literal: true

module PdfHelper
  def stub_pdf_generation(response_body = nil, status = 200)
    response_body ||= File.read(Rails.root.join("spec/fixtures/blank.pdf"))

    stub_request(:post, "#{ENV["LAGO_PDF_URL"]}/forms/chromium/convert/html")
      .to_return(body: response_body, status: status)
  end
end
