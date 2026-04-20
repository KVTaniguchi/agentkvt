module V1
  module Agent
    class EphemeralPinsController < BaseController
      def index
        pins = current_workspace.ephemeral_pins.active.recent_first
        render json: { ephemeral_pins: pins.map { |p| serialize_ephemeral_pin(p) } }
      end

      def create
        pin = current_workspace.ephemeral_pins.create!(ephemeral_pin_params)
        render json: { ephemeral_pin: serialize_ephemeral_pin(pin) }, status: :created
      end

      def destroy
        pin = current_workspace.ephemeral_pins.find(params[:id])
        pin.destroy!
        head :no_content
      end

      def purge_expired
        count = current_workspace.ephemeral_pins.expired.delete_all
        render json: { purged_count: count }
      end

      private

      def ephemeral_pin_params
        params.require(:ephemeral_pin).permit(:content, :category, :strength, :expires_at)
      end
    end
  end
end
