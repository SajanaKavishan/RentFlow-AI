import './App.css'
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
          <a href="#viewing-requests">Viewing requests</a>
        </div>
      </nav>
      <div id="viewing-requests">
        <ViewingRequestsPage />
      </div>
    </div>
  )
}

export default App
