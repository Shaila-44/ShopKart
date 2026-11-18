module Api
  module V1
    class RegistrationsController < ApplicationController
      allow_unauthenticated_access only: :create

      def create
        user = User.new(registration_params)
        # Self-registration always creates a customer; roles are assigned by admins only.
        user.role = :customer
        # Ensure valid organization is assigned (fixes ID mismatch)
        user.organization = Organization.find_by(slug: "lookz-men") || Organization.first

        if user.save
          token = JsonWebToken.encode(user_id: user.id)
          render json: {
            success: true,
            token: token,
            email: user.email_address,
            phone_number: user.phone_number,
            role: user.role,
            message: "User registered successfully"
          }, status: :created
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def registration_params
        params.require(:user).permit(:email_address, :phone_number, :password, :password_confirmation, :name)
      end
    end
  end
end
