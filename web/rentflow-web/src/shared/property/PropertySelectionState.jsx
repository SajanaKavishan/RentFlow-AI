export default function PropertySelectionState({ className }) {
  return (
    <section className={className} role="status">
      <h2>Select a property</h2>
      <p>
        Property integration pending: Property Management must provide an
        authenticated list of your properties and a landlord property
        workspace before this workspace can open with a verified property
        selection.
      </p>
    </section>
  )
}
