Rails.application.routes.draw do
  # Devise routes for authentication
  devise_for :users

  # Root route
  root "home#index"

  # Authenticated routes
  authenticate :user do
    resources :shops do
      resources :products, except: [:show] do
        collection do
          post :bulk_update_margin
        end
      end
      resources :imports, only: [:index, :new, :create, :show] do
        member do
          post :start_processing
          get :preview
        end
      end
    end

    # Standalone product show (for viewing product details)
    resources :products, only: [:show]
  end

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # PWA files
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
end
