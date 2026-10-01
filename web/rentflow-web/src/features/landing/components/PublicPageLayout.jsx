import PublicFooter from './PublicFooter.jsx'
import PublicHeader from './PublicHeader.jsx'
import '../landing.css'
import '../public-pages.css'

export default function PublicPageLayout({ children }) {
  return <div className="landing-page public-page">
    <PublicHeader solid />
    {children}
    <PublicFooter />
  </div>
}

