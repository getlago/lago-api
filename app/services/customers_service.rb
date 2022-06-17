# frozen_string_literal: true

class CustomersService < BaseService
  def create_from_api(organization:, params:)
    customer = organization.customers.find_or_initialize_by(customer_id: params[:customer_id])

    customer.name = params[:name] if params.key?(:name)
    customer.country = params[:country]&.upcase if params.key?(:country)
    customer.address_line1 = params[:address_line1] if params.key?(:address_line1)
    customer.address_line2 = params[:address_line2] if params.key?(:address_line2)
    customer.state = params[:state] if params.key?(:state)
    customer.zipcode = params[:zipcode] if params.key?(:zipcode)
    customer.email = params[:email] if params.key?(:email)
    customer.city = params[:city] if params.key?(:city)
    customer.url = params[:url] if params.key?(:url)
    customer.phone = params[:phone] if params.key?(:phone)
    customer.logo_url = params[:logo_url] if params.key?(:logo_url)
    customer.legal_name = params[:legal_name] if params.key?(:legal_name)
    customer.legal_number = params[:legal_number] if params.key?(:legal_number)
    customer.vat_rate = params[:vat_rate] if params.key?(:vat_rate)

    customer.save!

    assign_billing_configuration(customer, params)

    result.customer = customer
    result
  rescue ActiveRecord::RecordInvalid => e
    result.fail_with_validations!(e.record)
  end

  def create(**args)
    customer = Customer.create!(
      organization_id: args[:organization_id],
      customer_id: args[:customer_id],
      name: args[:name],
      country: args[:country]&.upcase,
      address_line1: args[:address_line1],
      address_line2: args[:address_line2],
      state: args[:state],
      zipcode: args[:zipcode],
      email: args[:email],
      city: args[:city],
      url: args[:url],
      phone: args[:phone],
      logo_url: args[:logo_url],
      legal_name: args[:legal_name],
      legal_number: args[:legal_number],
      vat_rate: args[:vat_rate],
    )

    result.customer = customer
    result
  rescue ActiveRecord::RecordInvalid => e
    result.fail_with_validations!(e.record)
  end

  def update(**args)
    customer = result.user.customers.find_by(id: args[:id])
    return result.fail!('not_found') unless customer

    customer.name = args[:name] if args.key?(:name)
    customer.country = args[:country]&.upcase if args.key?(:country)
    customer.address_line1 = args[:address_line1] if args.key?(:address_line1)
    customer.address_line2 = args[:address_line2] if args.key?(:address_line2)
    customer.state = args[:state] if args.key?(:state)
    customer.zipcode = args[:zipcode] if args.key?(:zipcode)
    customer.email = args[:email] if args.key?(:email)
    customer.city = args[:city] if args.key?(:city)
    customer.url = args[:url] if args.key?(:url)
    customer.phone = args[:phone] if args.key?(:phone)
    customer.logo_url = args[:logo_url] if args.key?(:logo_url)
    customer.legal_name = args[:legal_name] if args.key?(:legal_name)
    customer.legal_number = args[:legal_number] if args.key?(:legal_number)
    customer.vat_rate = args[:vat_rate] if args.key?(:vat_rate)

    # NOTE: Customer_id is not editable if customer is attached to subscriptions
    if !customer.attached_to_subscriptions? && args.key?(:customer_id)
      customer.customer_id = args[:customer_id]
    end

    customer.save!

    result.customer = customer
    result
  rescue ActiveRecord::RecordInvalid => e
    result.fail_with_validations!(e.record)
  end

  def destroy(id:)
    customer = result.user.customers.find_by(id: id)
    return result.fail!('not_found') unless customer

    unless customer.deletable?
      return result.fail!(
        'forbidden',
        'Customer is attached to an active subscription',
      )
    end

    customer.destroy!

    result.customer = customer
    result
  end

  private

  def assign_billing_configuration(customer, params)
    return unless params.key?(:billing_configuration)

    billing_configuration = params[:billing_configuration]

    unless billing_configuration[:payment_provider] == 'stripe'
      customer.update!(payment_provider: nil)
      return
    end

    customer.update!(payment_provider: 'stripe')

    create_result = PaymentProviderCustomers::CreateService.new(customer).create(
      customer_class: PaymentProviderCustomers::StripeCustomer,
      payment_provider_id: customer.organization.stripe_payment_provider&.id,
      params: billing_configuration,
    )
    create_result.throw_error unless create_result.success?
  end
end
