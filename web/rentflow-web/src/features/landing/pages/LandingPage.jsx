import ConnectedExperienceSection from '../components/ConnectedExperienceSection.jsx'
import FinalCtaSection from '../components/FinalCtaSection.jsx'
import HeroSection from '../components/HeroSection.jsx'
import JourneySection from '../components/JourneySection.jsx'
import PlatformSection from '../components/PlatformSection.jsx'
import PublicFooter from '../components/PublicFooter.jsx'
import PublicHeader from '../components/PublicHeader.jsx'
import SmartAssistanceSection from '../components/SmartAssistanceSection.jsx'
import { useLandingSignIn } from '../useLandingSignIn.js'
import '../landing.css'

export default function LandingPage() {
  const signIn = useLandingSignIn()

  return <div className="landing-page">
    <div className="landing-hero-wrap">
      <PublicHeader {...signIn} />
      <HeroSection />
    </div>
    <main>
      <PlatformSection />
      <JourneySection />
      <SmartAssistanceSection />
      <ConnectedExperienceSection />
      <FinalCtaSection {...signIn} />
    </main>
    <PublicFooter {...signIn} />
  </div>
}
