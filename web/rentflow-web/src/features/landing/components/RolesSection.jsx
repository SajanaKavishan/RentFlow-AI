import Icon from '../../../shared/ui/Icons.jsx'

const roles = [
  { icon: 'user', title: 'Tenant', items: ['Discover properties', 'Request viewings', 'Submit applications', 'Manage documents'] },
  { icon: 'building', title: 'Landlord / Property Manager', items: ['Manage listings', 'Review requests and applications', 'Coordinate leases/payments', 'Handle approvals'] },
  { icon: 'tools', title: 'Maintenance Technician', items: ['Receive assigned work', 'Track job progress'] },
  { icon: 'home', title: 'System Admin', items: ['Monitor platform operations and users'] },
]

export default function RolesSection() {
  return <section id="roles" className="landing-section landing-roles" aria-labelledby="roles-title">
    <div className="landing-container">
      <div className="landing-section__heading">
        <p className="landing-eyebrow">Purpose-built workspaces</p>
        <h2 id="roles-title">Built for every part of the rental process.</h2>
      </div>
      <div className="landing-card-grid landing-card-grid--roles">
        {roles.map((role) => <article className="landing-card landing-role-card" key={role.title}>
          <span className="landing-card__icon"><Icon name={role.icon} size={23} /></span>
          <h3>{role.title}</h3>
          <ul>{role.items.map((item) => <li key={item}><span aria-hidden="true">✓</span>{item}</li>)}</ul>
        </article>)}
      </div>
    </div>
  </section>
}
