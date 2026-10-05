import { useAuth } from '../../features/auth/useAuth.js'
import TechnicianJobCard from './TechnicianJobCard.jsx'
import useTechnicianWork from './useTechnicianWork.js'
import './technician-assigned-work.css'

export default function TechnicianWorkHistoryPage() {
  const { user } = useAuth()
  const { status, requests, error, retry } = useTechnicianWork(user.id)
  const completed = requests.filter((item) => item.status === 'Completed').sort((a, b) => (Date.parse(b.completedAt) || 0) - (Date.parse(a.completedAt) || 0))
  return <main className="shared-page technician-page">
    <header className="technician-page__header"><div><h1>Work History</h1><p>{status === 'ready' ? `${completed.length} completed ${completed.length === 1 ? 'job' : 'jobs'}` : 'Your completed maintenance work'}</p></div></header>
    {status === 'loading' && <p role="status" aria-busy="true">Loading work history…</p>}
    {status === 'error' && <div className="assigned-work-state" role="alert"><h2>Work history could not be loaded</h2><p>{error}</p><button className="shared-button" onClick={retry}>Try again</button></div>}
    {status === 'ready' && !completed.length && <div className="assigned-work-state"><h2>No completed work yet</h2><p>Completed jobs will appear here.</p></div>}
    <div className="assigned-work-list">{completed.map((request) => <TechnicianJobCard key={request.id} request={request} history />)}</div>
  </main>
}
