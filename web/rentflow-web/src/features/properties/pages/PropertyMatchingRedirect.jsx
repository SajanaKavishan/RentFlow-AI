import { Navigate } from 'react-router-dom'

export default function PropertyMatchingRedirect() {
  return <Navigate to="/modules/properties?preferences=edit" replace />
}
