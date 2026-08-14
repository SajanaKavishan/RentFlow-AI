import './App.css'
import RentalApplicationsPage from './features/rentalApplications/pages/RentalApplicationsPage.jsx'
import ViewingRequestsPage from './features/viewings/pages/ViewingRequestsPage.jsx'

function App() {
  return (
    <div className="app-shell">
      <nav className="app-nav" aria-label="Development navigation">
        <a className="app-brand" href="/">
          <span aria-hidden="true">R</span>
          RentFlow
        </a>
        <div className="app-nav__current">
          <span className="dev-label">Development</span>
          <div className="app-nav__links">
            <a href="#viewing-requests">Viewing requests</a>
            <a href="#rental-applications">Rental applications</a>
          </div>
        </div>
      </nav>
      <div id="viewing-requests">
        <ViewingRequestsPage />
      </div>
      <div id="rental-applications" className="app-section app-section--alternate">
        <RentalApplicationsPage />
      </div>
    </div>
  )
}

export default App
