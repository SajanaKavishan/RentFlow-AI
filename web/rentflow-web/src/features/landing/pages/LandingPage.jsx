import ConnectedExperienceSection from '../components/ConnectedExperienceSection.jsx'
import ExperienceRailSection from '../components/ExperienceRailSection.jsx'
import FeedbackSection from '../components/FeedbackSection.jsx'
import HeroSection from '../components/HeroSection.jsx'
import JourneySection from '../components/JourneySection.jsx'
import PlatformSection from '../components/PlatformSection.jsx'
import PublicFooter from '../components/PublicFooter.jsx'
import PublicHeader from '../components/PublicHeader.jsx'
import SmartAssistanceSection from '../components/SmartAssistanceSection.jsx'
import { useLandingMotion } from '../useLandingMotion.js'
import '../landing.css'

export default function LandingPage() {
  const motionRoot = useLandingMotion()

  return <div className="landing-page" ref={motionRoot}>
    <div className="landing-hero-wrap">
      <PublicHeader />
      <HeroSection />
    </div>
    <main>
      <PlatformSection />
      <JourneySection />
      <SmartAssistanceSection />
      <ConnectedExperienceSection />
      <ExperienceRailSection />
      <FeedbackSection />
    </main>
    <PublicFooter />
  </div>
}
