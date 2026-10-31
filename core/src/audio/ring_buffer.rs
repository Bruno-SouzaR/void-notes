/// Standard sample rate used across all void-notes audio subsystems.
pub const SAMPLE_RATE: u32 = 16_000;

/// Fixed-capacity circular audio buffer for low-latency sliding window processing.
///
/// Designed to store 16 kHz mono `f32` audio samples with zero allocations during streaming.
#[derive(Debug, Clone)]
pub struct AudioRingBuffer {
    buffer: Vec<f32>,
    capacity: usize,
    write_pos: usize,
    total_written: usize,
}

impl AudioRingBuffer {
    /// Creates a new buffer with the specified sample capacity.
    pub fn new(capacity: usize) -> Self {
        assert!(capacity > 0, "AudioRingBuffer capacity must be > 0");
        Self {
            buffer: vec![0.0; capacity],
            capacity,
            write_pos: 0,
            total_written: 0,
        }
    }

    /// Creates a buffer calibrated to store a specific duration in seconds at 16 kHz.
    pub fn with_duration_seconds(seconds: f32) -> Self {
        let capacity = (seconds * SAMPLE_RATE as f32).round() as usize;
        Self::new(capacity)
    }

    /// Returns the maximum sample capacity of the ring buffer.
    pub fn capacity(&self) -> usize {
        self.capacity
    }

    /// Returns the current number of valid samples stored (capped at capacity).
    pub fn len(&self) -> usize {
        self.total_written.min(self.capacity)
    }

    /// Returns true if no samples have been written yet.
    pub fn is_empty(&self) -> bool {
        self.total_written == 0
    }

    /// Clears the buffer and resets write pointers.
    pub fn clear(&mut self) {
        self.buffer.fill(0.0);
        self.write_pos = 0;
        self.total_written = 0;
    }

    /// Pushes incoming f32 samples into the ring buffer without reallocations.
    pub fn push_samples(&mut self, samples: &[f32]) {
        for &sample in samples {
            self.buffer[self.write_pos] = sample;
            self.write_pos = (self.write_pos + 1) % self.capacity;
            self.total_written = self.total_written.saturating_add(1);
        }
    }

    /// Pushes incoming 16-bit signed PCM samples converted to normalized f32 [-1.0, 1.0].
    pub fn push_pcm16(&mut self, samples: &[i16]) {
        for &sample in samples {
            let normalized = sample as f32 / 32768.0;
            self.buffer[self.write_pos] = normalized;
            self.write_pos = (self.write_pos + 1) % self.capacity;
            self.total_written = self.total_written.saturating_add(1);
        }
    }

    /// Extracts the most recent `n` samples in chronological order.
    ///
    /// If `n` is greater than the available samples, returns all available samples.
    pub fn get_last_n_samples(&self, n: usize) -> Vec<f32> {
        let count = n.min(self.len());
        if count == 0 {
            return Vec::new();
        }

        let mut output = Vec::with_capacity(count);
        // Calculate the starting read index in the circular buffer
        let start_index = (self.write_pos + self.capacity - count) % self.capacity;

        for i in 0..count {
            let idx = (start_index + i) % self.capacity;
            output.push(self.buffer[idx]);
        }

        output
    }

    /// Dumps all currently held samples in chronological order.
    pub fn to_vec(&self) -> Vec<f32> {
        self.get_last_n_samples(self.len())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ring_buffer_basic_push_and_retrieval() {
        let mut rb = AudioRingBuffer::new(5);
        assert_eq!(rb.capacity(), 5);
        assert_eq!(rb.len(), 0);
        assert!(rb.is_empty());

        rb.push_samples(&[1.0, 2.0, 3.0]);
        assert_eq!(rb.len(), 3);
        assert_eq!(rb.get_last_n_samples(3), vec![1.0, 2.0, 3.0]);
        assert_eq!(rb.get_last_n_samples(2), vec![2.0, 3.0]);
        assert_eq!(rb.get_last_n_samples(10), vec![1.0, 2.0, 3.0]); // bounded by len
    }

    #[test]
    fn test_ring_buffer_wrapping_overwrite() {
        let mut rb = AudioRingBuffer::new(4);
        // Write 6 samples: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
        // In buffer of capacity 4, last 4 should be [3.0, 4.0, 5.0, 6.0]
        rb.push_samples(&[1.0, 2.0, 3.0, 4.0]);
        assert_eq!(rb.len(), 4);
        assert_eq!(rb.to_vec(), vec![1.0, 2.0, 3.0, 4.0]);

        rb.push_samples(&[5.0, 6.0]);
        assert_eq!(rb.len(), 4);
        assert_eq!(rb.to_vec(), vec![3.0, 4.0, 5.0, 6.0]);
        assert_eq!(rb.get_last_n_samples(2), vec![5.0, 6.0]);
    }

    #[test]
    fn test_ring_buffer_pcm16_conversion() {
        let mut rb = AudioRingBuffer::new(2);
        rb.push_pcm16(&[0, 32767]);
        let samples = rb.to_vec();
        assert_eq!(samples.len(), 2);
        assert_eq!(samples[0], 0.0);
        assert!((samples[1] - 0.999969).abs() < 1e-4);
    }

    #[test]
    fn test_ring_buffer_with_duration() {
        // 0.5s at 16000Hz = 8000 samples
        let rb = AudioRingBuffer::with_duration_seconds(0.5);
        assert_eq!(rb.capacity(), 8000);
    }
}
