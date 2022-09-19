# frozen_string_literal: true

class ErrorSerializer < ModelSerializer
  def serialize
    {
      status: model.status,
      error: (model.status == 404) ? 'Not found' : 'Unprocessable entity',
      message: model.error.to_s,
      input_params: model.input_params,
    }
  end
end
