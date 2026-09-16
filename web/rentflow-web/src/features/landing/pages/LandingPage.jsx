import AiReviewSection from '../components/AiReviewSection.jsx'
import FinalCtaSection from '../components/FinalCtaSection.jsx'
import HeroSection from '../components/HeroSection.jsx'
import JourneySection from '../components/JourneySection.jsx'
import PlatformSection from '../components/PlatformSection.jsx'
import PublicFooter from '../components/PublicFooter.jsx'
import PublicHeader from '../components/PublicHeader.jsx'
import RolesSection from '../components/RolesSection.jsx'
import { useLandingSignIn } from '../useLandingSignIn.js'
import '../landing.css'

export default function LandingPage() {
  const signIn = useLandingSignIn()

  return <div className="landing-page">
    <div className="landing-hero-wrap">
      <PublicHeader {...signIn} />
      <HeroSection {...signIn} />
    </div>
    <main>
      <PlatformSection />
      <JourneySection />
      <AiReviewSection />
      <RolesSection />
      <FinalCtaSection {...signIn} />
    </main>
    <PublicFooter {...signIn} />
  </div>
}
