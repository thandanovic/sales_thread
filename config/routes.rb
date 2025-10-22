Rails.application.routes.draw do
  # Devise routes for authentication
  devise_for :users

  # Root route
  root "home#index"

  # Authenticated routes
  authenticate :user do
    resources :shops do
      member do
        post :test_olx_connection
      end

      resources :products do
        collection do
          post :bulk_update_margin
          delete :bulk_destroy
        end
        member do
          post :publish_to_olx
          post :publish_to_olx_live
          post :update_on_olx
          post :unpublish_from_olx
          delete :remove_from_olx
        end
      end
      resources :imports, only: [:index, :new, :create, :show] do
        member do
          post :start_processing
          get :preview
        end
      end
      resources :olx_category_templates do
        collection do
          get :load_attributes
        end
      end
    end
  end

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # PWA files
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
end
