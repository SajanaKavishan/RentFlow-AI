import { useState } from 'react'
import ApplicationDocumentCard from '../../features/applicationDocuments/components/ApplicationDocumentCard.jsx'
import { ApplicationDocumentApiError, downloadApplicationDocument, getApplicationDocuments } from '../../features/applicationDocuments/services/applicationDocumentApiService.js'
import { getMyApplications, RentalApplicationApiError } from '../../features/rentalApplications/services/rentalApplicationApiService.js'
import Icon from '../ui/Icons.jsx'
import '../../features/rentalApplications/rentalApplications.css'
import '../../features/applicationDocuments/applicationDocuments.css'

function ApplicationDocuments({ applicationId }) {
  const [expanded, setExpanded] = useState(false)
  const [state, setState] = useState({ status: 'idle', documents: [], error: '' })
  const [downloadingId, setDownloadingId] = useState(null)
  const [downloadError, setDownloadError] = useState({ id: null, message: '' })

  async function loadDocuments() {
    setState({ status: 'loading', documents: [], error: '' })
    try {
      const documents = await getApplicationDocuments(applicationId)
      setState({ status: 'ready', documents, error: '' })
    } catch (error) {
      setState({ status: 'error', documents: [], error: error instanceof ApplicationDocumentApiError
        ? error.message : 'Unable to load these documents. Please try again.' })
    }
  }

  function toggle() {
    const next = !expanded
    setExpanded(next)
    if (next && state.status === 'idle') loadDocuments()
  }

  async function openDocument(document) {
    if (downloadingId) return
    setDownloadingId(document.id)
    setDownloadError({ id: null, message: '' })
    try {
      await downloadApplicationDocument(document.id)
    } catch (error) {
      setDownloadError({ id: document.id, message: error instanceof ApplicationDocumentApiError
        ? error.message : 'Unable to open this document. Please try again.' })
    } finally {
      setDownloadingId(null)
    }
  }

  return <div className="profile-application">
    <button className="profile-application__toggle" type="button" onClick={toggle} aria-expanded={expanded} aria-controls={`profile-documents-${applicationId}`}>
      <span>Application <code>{applicationId}</code></span>
      <span>{expanded ? 'Hide documents' : 'Show documents'}</span>
    </button>
    {expanded && <div className="profile-application__body" id={`profile-documents-${applicationId}`}>
      {state.status === 'loading' && <p role="status">Loading documents…</p>}
      {state.status === 'error' && <div role="alert"><p>{state.error}</p><button className="shared-button shared-button--outline" type="button" onClick={loadDocuments}>Retry documents</button></div>}
      {state.status === 'ready' && state.documents.length === 0 && <p>No documents have been added to this application.</p>}
      {state.status === 'ready' && state.documents.length > 0 && <div className="profile-application__documents">
        {state.documents.map((document) => <ApplicationDocumentCard key={document.id} document={document} isDownloading={downloadingId === document.id} downloadError={downloadError.id === document.id ? downloadError.message : ''} onDownload={openDocument} />)}
      </div>}
    </div>}
  </div>
}

export default function TenantApplicationDocuments() {
  const [expanded, setExpanded] = useState(false)
  const [state, setState] = useState({ status: 'idle', applications: [], error: '' })

  async function loadApplications() {
    setState({ status: 'loading', applications: [], error: '' })
    try {
      const applications = await getMyApplications()
      if (!Array.isArray(applications) || applications.some((item) => typeof item?.id !== 'string' || !item.id)) {
        throw new TypeError('Invalid application list')
      }
      setState({ status: 'ready', applications, error: '' })
    } catch (error) {
      setState({ status: 'error', applications: [], error: error instanceof RentalApplicationApiError
        ? error.message : 'Unable to load your applications. Please try again.' })
    }
  }

  function toggle() {
    const next = !expanded
    setExpanded(next)
    if (next && state.status === 'idle') loadApplications()
  }

  return <div className="profile-documents">
    <button className="profile-action profile-action--available" type="button" onClick={toggle} aria-expanded={expanded} aria-controls="profile-tenant-documents">
      <span className="profile-action__icon"><Icon name="document" size={20} /></span>
      <span className="profile-action__copy"><strong>Application documents</strong><small>View files attached to your rental applications.</small></span>
      <Icon name={expanded ? 'close' : 'arrow'} size={18} />
    </button>
    {expanded && <div className="profile-documents__body" id="profile-tenant-documents">
      {state.status === 'loading' && <p role="status">Loading your applications…</p>}
      {state.status === 'error' && <div role="alert"><p>{state.error}</p><button className="shared-button shared-button--outline" type="button" onClick={loadApplications}>Retry applications</button></div>}
      {state.status === 'ready' && state.applications.length === 0 && <p>No rental applications are available for this account.</p>}
      {state.status === 'ready' && state.applications.length > 0 && <div className="profile-documents__list">
        {state.applications.map((application) => <ApplicationDocuments key={application.id} applicationId={application.id} />)}
      </div>}
    </div>}
  </div>
}
