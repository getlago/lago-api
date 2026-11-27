# frozen_string_literal: true

module ViesHelper
  VIES_ENDPOINT = "https://ec.europa.eu/taxation_customs/vies/services/checkVatService"

  # VIES answers that the VAT number is valid. Valvat skips the call for an invalid format (like YY123).
  def mock_vies_check!(vat_number)
    stub_vies_request(vat_number).to_return(
      status: 200,
      body: vies_soap_envelope(
        "<ns2:checkVatResponse xmlns:ns2=\"urn:ec.europa.eu:taxud:vies:services:checkVat:types\">" \
        "<ns2:countryCode>#{vat_number[0..1].upcase}</ns2:countryCode>" \
        "<ns2:vatNumber>#{vat_number[2..].upcase}</ns2:vatNumber>" \
        "<ns2:valid>true</ns2:valid>" \
        "</ns2:checkVatResponse>"
      )
    )
  end

  # VIES answers with a fault, so the check stays pending and is retried later.
  # MS_UNAVAILABLE is a member state maintenance, GLOBAL_MAX_CONCURRENT_REQ a rate limit.
  def mock_vies_check_unavailable!(vat_number, fault: "MS_UNAVAILABLE")
    stub_vies_request(vat_number).to_return(
      status: 200,
      body: vies_soap_envelope("<env:Fault><faultcode>env:Server</faultcode><faultstring>#{fault}</faultstring></env:Fault>")
    )
  end

  private

  # Matches only a checkVat request for this VAT number, so a check of another number is not answered.
  def stub_vies_request(vat_number)
    expected = {country_code: vat_number[0..1].upcase, vat_number: vat_number[2..].upcase}

    stub_request(:post, VIES_ENDPOINT).with { |request| vies_check_request(request.body) == expected }
  end

  def vies_check_request(body)
    check = REXML::Document.new(body).get_elements("//urn:checkVat").first
    return unless check

    {
      country_code: check.get_elements("urn:countryCode").first&.text,
      vat_number: check.get_elements("urn:vatNumber").first&.text
    }
  end

  def vies_soap_envelope(body)
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" \
      "<env:Envelope xmlns:env=\"http://schemas.xmlsoap.org/soap/envelope/\"><env:Body>#{body}</env:Body></env:Envelope>"
  end
end
