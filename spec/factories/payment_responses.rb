# frozen_string_literal: true

FactoryBot.define do
  sequence :adyen_payments_response do
    Adyen::AdyenResult.new(
      {
        "additionalData" => {
          "recurringProcessingModel" => "UnscheduledCardOnFile"
        },
        "pspReference" => SecureRandom.uuid,
        "resultCode" => "Authorised",
        "merchantReference" => SecureRandom.uuid
      }.to_json,
      {},
      200
    )
  end

  sequence :adyen_payments_error_response do
    Adyen::AdyenResult.new(
      {
        "errorType" => "validation",
        "message" => "There are no payment methods available for the given parameters."
      }.to_json,
      {},
      422
    )
  end

  sequence :adyen_payment_links_response do
    Adyen::AdyenResult.new(
      {
        "amount" => {
          "currency" => "EUR",
          "value" => 0
        },
        "expiresAt" => "2023-05-19T10:00:19+02:00",
        "merchantAccount" => SecureRandom.uuid,
        "recurringProcessingModel" => "UnscheduledCardOnFile",
        "reference" => SecureRandom.uuid,
        "reusable" => false,
        "shopperReference" => SecureRandom.uuid,
        "storePaymentMethodMode" => "enabled",
        "id" => SecureRandom.uuid,
        "status" => "active",
        "url" => "https://test.adyen.link/test"
      }.to_json,
      {},
      200
    )
  end

  sequence :adyen_payment_links_error_response do
    Adyen::AdyenResult.new(
      {
        "errorType" => "validation",
        "message" => "There are no payment methods available for the given parameters."
      }.to_json,
      {},
      422
    )
  end

  sequence :adyen_payment_methods_response do
    Adyen::AdyenResult.new(
      {
        "paymentMethods" => [
          {
            "brands" => %w[amex bcmc cartebancaire mc visa visadankort],
            "name" => "Credit Card",
            "type" => "scheme"
          }
        ],
        "storedPaymentMethods" => [
          {
            "brand" => "visa",
            "expiryMonth" => "03",
            "expiryYear" => "30",
            "holderName" => "Checkout Shopper PlaceHolder",
            "id" => SecureRandom.uuid,
            "lastFour" => "1234",
            "name" => "VISA",
            "networkTxReference" => SecureRandom.uuid,
            "supportedRecurringProcessingModels" => %w[CardOnFile Subscription UnscheduledCardOnFile],
            "supportedShopperInteractions" => %w[Ecommerce ContAuth],
            "type" => "scheme"
          }
        ]
      }.to_json,
      {},
      200
    )
  end
end
