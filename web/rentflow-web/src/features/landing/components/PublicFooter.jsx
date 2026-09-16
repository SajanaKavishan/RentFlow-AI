import { BrandMark } from '../../../shared/ui/BrandLogo.jsx'

export default function PublicFooter() {
  return <footer className="public-footer">
    <div className="landing-container public-footer__inner">
      <a className="public-footer__brand" href="#top" aria-label="RentFlow AI home"><BrandMark className="public-footer__mark" decorative /><span>RentFlow <strong>AI</strong></span></a>
      <p className="public-footer__copyright">&copy; 2026 RentFlow AI. All rights reserved.</p>
    </div>
  </footer>
}
