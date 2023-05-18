FactoryBot.define do
  sequence :adyen_payments_response do
    OpenStruct.new(
      response: {
        "additionalData" => {
            "recurringProcessingModel" => "UnscheduledCardOnFile"
        },
        "pspReference" => "#{SecureRandom.uuid}",
        "resultCode" => "Authorised",
        "amount" => {
            "currency" => "USD",
            "value" => 1000
        },
        "merchantReference" => "#{SecureRandom.uuid}",
        "paymentMethod" => {
            "brand" => "amex",
            "type" => "scheme"
        }
      }
    )
  end

  sequence :adyen_payment_links_response do
    OpenStruct.new(
      response: {
        "amount" => {
            "currency" => "EUR",
            "value" => 0
        },
        "expiresAt" => "2023-05-19T10:00:19+02:00",
        "merchantAccount" => "#{SecureRandom.uuid}",
        "recurringProcessingModel" => "UnscheduledCardOnFile",
        "reference" => "#{SecureRandom.uuid}",
        "reusable" => false,
        "shopperReference" => "#{SecureRandom.uuid}",
        "storePaymentMethodMode" => "enabled",
        "id" => "#{SecureRandom.uuid}",
        "status" => "active",
        "url" => "https://test.adyen.link/test"
      }
    )
  end
end
