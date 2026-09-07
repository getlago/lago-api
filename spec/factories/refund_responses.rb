# frozen_string_literal: true

FactoryBot.define do
  sequence :adyen_refunds_response do
    Adyen::AdyenResult.new(
      {
        "merchantAccount" => SecureRandom.uuid,
        "pspReference" => SecureRandom.uuid,
        "paymentPspReference" => SecureRandom.uuid,
        "status" => "received",
        "amount" => {
          "currency" => "CHF",
          "value" => 134
        }
      }.to_json,
      {},
      200
    )
  end
end
