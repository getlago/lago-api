# frozen_string_literal: true

module AnrokHelper
  NANGO_ACTION_ENDPOINT = "https://api.nango.dev/action/trigger"

  # Stubs one Anrok tax action sent through Nango. The stub matches only a request with this action,
  # the Nango headers of the integration and exactly this invoice payload, so a call with other data
  # is not answered. Each fee is taxed 990 cents, as in the success fixture.
  #
  #   stub_anrok_taxes("anrok-create-ephemeral-transaction", integration_customer:, invoice:,
  #     fees: [{"item_key" => charge.id, "item_id" => charge.id, "item_code" => nil, "amount_cents" => 10_000}])
  def stub_anrok_taxes(action_name, integration_customer:, invoice:, fees:)
    integration = integration_customer.integration

    stub_request(:post, NANGO_ACTION_ENDPOINT)
      .with(
        headers: {"Connection-Id" => integration.connection_id, "Provider-Config-Key" => "anrok"},
        body: {action_name:, input: anrok_invoice_payload(integration_customer:, invoice:, fees:)}
      )
      .to_return do |request|
        {body: anrok_taxes_response(JSON.parse(request.body).dig("input", 0, "fees")).to_json}
      end
  end

  private

  def anrok_invoice_payload(integration_customer:, invoice:, fees:)
    customer = integration_customer.customer
    shipping = customer.effective_shipping_address
    issuing_date = [invoice.issuing_date, 30.days.from_now.to_date].min.iso8601

    [
      {
        "issuing_date" => issuing_date,
        "currency" => invoice.currency,
        "contact" => {
          "external_id" => integration_customer.external_customer_id || customer.external_id,
          "name" => customer.name,
          "address_line_1" => shipping[:address_line1],
          "city" => shipping[:city],
          "zip" => shipping[:zipcode],
          "country" => shipping[:country],
          "taxable" => customer.tax_identification_number.present?,
          "tax_number" => customer.tax_identification_number
        },
        "fees" => fees,
        "tax_date" => issuing_date
      }
    ]
  end

  def anrok_taxes_response(fees)
    body = JSON.parse(File.read(Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/success_response.json")))
    taxed_invoice = body["succeededInvoices"].first
    fee_template = taxed_invoice["fees"].first
    taxed_invoice["fees"] = fees.map { |fee| fee_template.merge("item_id" => fee["item_id"]) }
    body
  end
end
