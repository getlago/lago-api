# frozen_string_literal: true

module Utils
  class PdfGenerator < BaseService
    include ActiveSupport::NumberHelper

    def initialize(template:, context:)
      @template = template
      @context = context

      super(nil)
    end

    def call
      result.io = StringIO.new(render_pdf)
      result
    end

    private

    attr_reader :template, :context

    def template_file
      File.read(Rails.root.join("app/views/templates/#{template}.slim"), encoding: 'UTF-8')
    end

    def render_html
      Slim::Template.new { template_file }.render(context)
    end

    def pdf_url
      URI.join(ENV['LAGO_PDF_URL'], '/forms/chromium/convert/html').to_s
    end

    def render_pdf
      http_client = LagoHttpClient::Client.new(pdf_url)

      response = http_client.post_multipart_file(
        render_html,
        'text/html',
        'index.html',
        scale: '1.28',
        marginTop: '0.42',
        marginBottom: '0.42',
        marginLeft: '0.42',
        marginRight: '0.42',
      )

      response.body.force_encoding('UTF-8')
    end
  end
end
