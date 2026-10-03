\# FoodSense



\## Track



Smart India Hackathon – AI-Powered Smart Food Waste Reduction and Sustainable Redistribution Ecosystem.



\## Problem Statement



Institutional kitchens and food processing units generate significant amounts

of avoidable food waste because food demand, production, inventory, surplus,

and redistribution are often managed independently.



FoodSense addresses this problem through a connected platform that helps

organizations:



\- Track inventory and expiry information

\- Record daily food preparation, consumption, and waste

\- Identify inventory risks

\- Generate operational recommendations

\- Forecast food demand

\- Predict potential surplus

\- Analyze historical waste

\- Connect surplus food with redistribution workflows

\- Assign delivery partners

\- Calculate traffic-aware delivery routes

\- Monitor delivery status and ETA



\## Solution



FoodSense is built as a Flutter application backed by Firebase and FastAPI.



\### Phase 1

\- Firebase Authentication

\- Organization setup

\- Organization members and roles

\- Inventory management

\- Daily food records

\- Record history

\- Inventory risk detection

\- Operational recommendations



\### Phase 2

\- Demand forecasting

\- Surplus prediction

\- Scenario comparison

\- Waste analysis



\### Redistribution Network

\- Delivery partner registration

\- Delivery job creation

\- Pickup and drop-off locations

\- Location search

\- Google Maps integration

\- Traffic-aware routing

\- ETA and distance

\- Delivery status tracking

\- Driver GPS updates



\## Technology Stack



\### Frontend

\- Flutter

\- Dart

\- GoRouter

\- Firebase Authentication

\- Cloud Firestore

\- Google Maps for Flutter

\- Geolocator



\### Backend

\- Python

\- FastAPI

\- Firebase Admin SDK

\- HTTPX



\### Cloud Services

\- Firebase Authentication

\- Cloud Firestore

\- Cloudinary

\- Google Maps Platform

\- Google Routes API

\- Google Places API (New)



\## How Cloudinary Is Used



FoodSense uses Cloudinary for food-related image storage instead of storing

image files directly in Firestore.



The architecture is:



Flutter

→ FastAPI

→ signed upload parameters

→ Cloudinary



The uploaded Cloudinary URL and public ID are stored with the corresponding

FoodSense record in Firestore.



Cloudinary is used for images associated with:

\- Food records

\- Inventory items

\- Surplus food



The Cloudinary API secret is stored only on the backend and is never exposed

to the Flutter application.



\## Firestore Data Model



The project uses organization-scoped collections:



organizations/{organizationId}

\- members

\- inventory

\- food\_records

\- forecasts

\- surplus

\- redistribution

\- delivery\_partners

\- deliveries

\- analytics

\- audit\_logs



\## How to Run



\### Flutter



```powershell

flutter pub get

dart format lib test

flutter analyze

flutter test

