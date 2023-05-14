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
end
