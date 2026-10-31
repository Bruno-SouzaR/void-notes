use void_notes_core::audio::AudioRingBuffer;

#[test]
fn test_ring_buffer_zero_alloc_stress() {
    // 1-second capacity = 16,000 samples
    let mut rb = AudioRingBuffer::new(16_000);
    let chunk: Vec<f32> = (0..480).map(|i| (i as f32) / 480.0).collect();

    // Stream 1,000,000 samples (over 2000 pushes) through the buffer
    let total_pushes = 1_000_000 / 480;
    for _ in 0..total_pushes {
        rb.push_samples(&chunk);
    }
    assert_eq!(rb.len(), 16_000); // Must remain clamped to capacity
    assert_eq!(rb.capacity(), 16_000);
    let last_samples = rb.get_last_n_samples(480);
    assert_eq!(last_samples.len(), 480);
    assert!((last_samples[0] - chunk[0]).abs() < 1e-6);
}

#[test]
fn test_ring_buffer_chronological_ordering() {
    let mut rb = AudioRingBuffer::new(4);
    // Sequence 1..=6
    rb.push_samples(&[1.0, 2.0, 3.0]);
    assert_eq!(rb.to_vec(), vec![1.0, 2.0, 3.0]);

    rb.push_samples(&[4.0, 5.0, 6.0]);
    // Capacity 4 must retain the latest 4 values in exact chronological sequence: [3.0, 4.0, 5.0, 6.0]
    assert_eq!(rb.to_vec(), vec![3.0, 4.0, 5.0, 6.0]);
}

#[test]
fn test_ring_buffer_partial_and_oversized_queries() {
    let mut rb = AudioRingBuffer::new(10);
    rb.push_samples(&[10.0, 20.0, 30.0]);

    assert_eq!(rb.get_last_n_samples(0), Vec::<f32>::new());
    assert_eq!(rb.get_last_n_samples(2), vec![20.0, 30.0]);
    assert_eq!(rb.get_last_n_samples(50), vec![10.0, 20.0, 30.0]); // Bounded by length
}

#[test]
fn test_ring_buffer_clear_resets_state() {
    let mut rb = AudioRingBuffer::new(10);
    rb.push_samples(&[1.0, 2.0, 3.0]);
    assert_eq!(rb.len(), 3);

    rb.clear();
    assert_eq!(rb.len(), 0);
    assert!(rb.is_empty());
    assert_eq!(rb.to_vec(), Vec::<f32>::new());
}
