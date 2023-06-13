class CheckoutsController < ApplicationController
    skip_before_action :is_authorized, :only => [:create, :complete]
    
    def create
        dev_url = "http://localhost:8000"
        prod_url = ""

        session = Stripe::Checkout::Session.create({
			metadata: {
				order_id: params['metadata']["order_id"]
			},
			shipping_address_collection: {allowed_countries: ['AU']},
			shipping_options: [
            	{
              		shipping_rate_data: {
                		type: 'fixed_amount',
                		fixed_amount: {
                  			amount: 0,
                  			currency: 'aud',
                		},
                		display_name: 'Free shipping',
                		delivery_estimate: {
                  			minimum: {
                    			unit: 'business_day',
                    			value: 5,
                  			},
                  			maximum: {
                    			unit: 'business_day',
                    			value: 7,
                  			},
                		},
              		},
            	},
				{
					shipping_rate_data: {
						type: 'fixed_amount',
						fixed_amount: {
							amount: 1500,
							currency: 'aud',
						},
						display_name: 'Next day air',
						delivery_estimate: {
							minimum: {
								unit: 'business_day',
								value: 1,
							},
							maximum: {
								unit: 'business_day',
								value: 1,
							},
						},
					},
				},
			],
            line_items: create_line_items(params),
            mode: 'payment',
            success_url: dev_url + '?success=true',
            cancel_url: dev_url + '?canceled=true',
        })
        render :json => { session: session.url }
    end

	def complete
		endpoint_secret = 'whsec_8916bf7946b1aa7e0b539e14643ce2a4d99d5a04ab10a9fedab1abac2c36c54e'
		event = nil

		begin
			sig_header = request.env['HTTP_STRIPE_SIGNATURE']
			payload = request.body.read
			event = Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
		rescue JSON::ParserError => e
			render :json => { status: 'Not ok'}, :status => :bad_request
		rescue Stripe::SignatureVerificationError => e
			puts 'bad request'
		end

		if event['type'] == 'checkout.session.completed'
			session = Stripe::Checkout::Session.retrieve({
				id: event['data']['object']['id'],
				expand: ['line_items'],
			})
			
			line_items = session.line_items
			order_id = session.metadata.order_id
			puts "session, #{session}"
			puts "hello, orderID: #{order_id}, Line items: #{line_items}"
			
			
			if order_id == 'None'
				# store payment intent in order
				# store order email
				# store shipping address

				order = Order.new # create a new order
				user = User.find_by email: 'guest@shop.co' # find guest user in DB
				order.user_id = user.id # assign order to the guest user account
				order.orderstatus = 'payment received'
				order.save

				products_array = [] #finding products
				line_items["data"].each do | product |
					db_product = Product.find_by product_name: product["description"]
					order.products << db_product
					cart_item = order.cart_items.where({product_id: db_product.id}).first
					cart_item.update_attribute(:quantity, product["quantity"].to_i)
				end

				order.save

			else
				update_order_status(order_id) unless order_id.nil?
				# send email
			end

		end
		# TODO: Post complete logic. Confirmed payment.
		# Update Order status
		# Update status to delivered or anything else thats not 'active'
		# Case 2 : For guest users
		# Get order information to create order


		render :json => { status: 'Ok'}, :status => :ok
	end

	private

	def create_line_items(params)
		arr = []

		params['lineItem'].each do | param |
			item = {
				price_data: {
					currency: 'aud',
					product_data: {
						name: param['name'],
					},
					unit_amount: (param['price'].to_f * 100).to_i
				},
				quantity: param['quantity'].to_i
			}
			arr << item
		end

		arr
	end

	def update_order_status(order_id)
		order = Order.find((order_id).to_i)
		order.orderstatus = 'Payment received'
		order.save
	end

end
